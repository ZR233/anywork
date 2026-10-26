// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'delegation_model_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DelegationModelReadHeader {

 ProductReadScopeIdentity get scope; DelegationModelReadTarget get target; ReadText get accountName; ModelDescriptorRead get descriptor; bool get available; ReadText? get unavailableReason; BillingKind get billingKind; ModelSelectionGuideRead? get guide; LocalModelPerformanceSummary get performance; AgentEvaluationSummary get evaluations; TypedListRef get recentEvaluations;
/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DelegationModelReadHeaderCopyWith<DelegationModelReadHeader> get copyWith => _$DelegationModelReadHeaderCopyWithImpl<DelegationModelReadHeader>(this as DelegationModelReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DelegationModelReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DelegationModelReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.accountName, _this.accountName) || other.accountName == _this.accountName)&&(identical(other.descriptor, _this.descriptor) || other.descriptor == _this.descriptor)&&(identical(other.available, _this.available) || other.available == _this.available)&&(identical(other.unavailableReason, _this.unavailableReason) || other.unavailableReason == _this.unavailableReason)&&(identical(other.billingKind, _this.billingKind) || other.billingKind == _this.billingKind)&&(identical(other.guide, _this.guide) || other.guide == _this.guide)&&(identical(other.performance, _this.performance) || other.performance == _this.performance)&&(identical(other.evaluations, _this.evaluations) || other.evaluations == _this.evaluations)&&(identical(other.recentEvaluations, _this.recentEvaluations) || other.recentEvaluations == _this.recentEvaluations));
}


@override
int get hashCode {
  final _this = this as DelegationModelReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.target,_this.accountName,_this.descriptor,_this.available,_this.unavailableReason,_this.billingKind,_this.guide,_this.performance,_this.evaluations,_this.recentEvaluations);
}



}

/// @nodoc
abstract mixin class $DelegationModelReadHeaderCopyWith<$Res>  {
  factory $DelegationModelReadHeaderCopyWith(DelegationModelReadHeader value, $Res Function(DelegationModelReadHeader) _then) = _$DelegationModelReadHeaderCopyWithImpl;
@useResult
$Res call({
 ProductReadScopeIdentity scope, DelegationModelReadTarget target, ReadText accountName, ModelDescriptorRead descriptor, bool available, ReadText? unavailableReason, BillingKind billingKind, ModelSelectionGuideRead? guide, LocalModelPerformanceSummary performance, AgentEvaluationSummary evaluations, TypedListRef recentEvaluations
});


$ProductReadScopeIdentityCopyWith<$Res> get scope;$DelegationModelReadTargetCopyWith<$Res> get target;$ReadTextCopyWith<$Res> get accountName;$ModelDescriptorReadCopyWith<$Res> get descriptor;$ReadTextCopyWith<$Res>? get unavailableReason;$ModelSelectionGuideReadCopyWith<$Res>? get guide;$LocalModelPerformanceSummaryCopyWith<$Res> get performance;$AgentEvaluationSummaryCopyWith<$Res> get evaluations;$TypedListRefCopyWith<$Res> get recentEvaluations;

}
/// @nodoc
class _$DelegationModelReadHeaderCopyWithImpl<$Res>
    implements $DelegationModelReadHeaderCopyWith<$Res> {
  _$DelegationModelReadHeaderCopyWithImpl(this._self, this._then);

  final DelegationModelReadHeader _self;
  final $Res Function(DelegationModelReadHeader) _then;

/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? target = null,Object? accountName = null,Object? descriptor = null,Object? available = null,Object? unavailableReason = freezed,Object? billingKind = null,Object? guide = freezed,Object? performance = null,Object? evaluations = null,Object? recentEvaluations = null,}) {
  return _then(DelegationModelReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ProductReadScopeIdentity,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as DelegationModelReadTarget,accountName: null == accountName ? _self.accountName : accountName // ignore: cast_nullable_to_non_nullable
as ReadText,descriptor: null == descriptor ? _self.descriptor : descriptor // ignore: cast_nullable_to_non_nullable
as ModelDescriptorRead,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,unavailableReason: freezed == unavailableReason ? _self.unavailableReason : unavailableReason // ignore: cast_nullable_to_non_nullable
as ReadText?,billingKind: null == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind,guide: freezed == guide ? _self.guide : guide // ignore: cast_nullable_to_non_nullable
as ModelSelectionGuideRead?,performance: null == performance ? _self.performance : performance // ignore: cast_nullable_to_non_nullable
as LocalModelPerformanceSummary,evaluations: null == evaluations ? _self.evaluations : evaluations // ignore: cast_nullable_to_non_nullable
as AgentEvaluationSummary,recentEvaluations: null == recentEvaluations ? _self.recentEvaluations : recentEvaluations // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadScopeIdentityCopyWith<$Res> get scope {

  return $ProductReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationModelReadTargetCopyWith<$Res> get target {

  return $DelegationModelReadTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountName {

  return $ReadTextCopyWith<$Res>(_self.accountName, (value) {
    return _then(_self.copyWith(accountName: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelDescriptorReadCopyWith<$Res> get descriptor {

  return $ModelDescriptorReadCopyWith<$Res>(_self.descriptor, (value) {
    return _then(_self.copyWith(descriptor: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get unavailableReason {
    if (_self.unavailableReason == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.unavailableReason!, (value) {
    return _then(_self.copyWith(unavailableReason: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionGuideReadCopyWith<$Res>? get guide {
    if (_self.guide == null) {
    return null;
  }

  return $ModelSelectionGuideReadCopyWith<$Res>(_self.guide!, (value) {
    return _then(_self.copyWith(guide: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LocalModelPerformanceSummaryCopyWith<$Res> get performance {

  return $LocalModelPerformanceSummaryCopyWith<$Res>(_self.performance, (value) {
    return _then(_self.copyWith(performance: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentEvaluationSummaryCopyWith<$Res> get evaluations {

  return $AgentEvaluationSummaryCopyWith<$Res>(_self.evaluations, (value) {
    return _then(_self.copyWith(evaluations: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get recentEvaluations {

  return $TypedListRefCopyWith<$Res>(_self.recentEvaluations, (value) {
    return _then(_self.copyWith(recentEvaluations: value));
  });
}
}


/// Adds pattern-matching-related methods to [DelegationModelReadHeader].
extension DelegationModelReadHeaderPatterns on DelegationModelReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DelegationModelReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DelegationModelReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DelegationModelReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _DelegationModelReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DelegationModelReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _DelegationModelReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadScopeIdentity scope,  DelegationModelReadTarget target,  ReadText accountName,  ModelDescriptorRead descriptor,  bool available,  ReadText? unavailableReason,  BillingKind billingKind,  ModelSelectionGuideRead? guide,  LocalModelPerformanceSummary performance,  AgentEvaluationSummary evaluations,  TypedListRef recentEvaluations)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DelegationModelReadHeader() when $default != null:
return $default(_that.scope,_that.target,_that.accountName,_that.descriptor,_that.available,_that.unavailableReason,_that.billingKind,_that.guide,_that.performance,_that.evaluations,_that.recentEvaluations);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadScopeIdentity scope,  DelegationModelReadTarget target,  ReadText accountName,  ModelDescriptorRead descriptor,  bool available,  ReadText? unavailableReason,  BillingKind billingKind,  ModelSelectionGuideRead? guide,  LocalModelPerformanceSummary performance,  AgentEvaluationSummary evaluations,  TypedListRef recentEvaluations)  $default,) {final _that = this;
switch (_that) {
case _DelegationModelReadHeader():
return $default(_that.scope,_that.target,_that.accountName,_that.descriptor,_that.available,_that.unavailableReason,_that.billingKind,_that.guide,_that.performance,_that.evaluations,_that.recentEvaluations);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadScopeIdentity scope,  DelegationModelReadTarget target,  ReadText accountName,  ModelDescriptorRead descriptor,  bool available,  ReadText? unavailableReason,  BillingKind billingKind,  ModelSelectionGuideRead? guide,  LocalModelPerformanceSummary performance,  AgentEvaluationSummary evaluations,  TypedListRef recentEvaluations)?  $default,) {final _that = this;
switch (_that) {
case _DelegationModelReadHeader() when $default != null:
return $default(_that.scope,_that.target,_that.accountName,_that.descriptor,_that.available,_that.unavailableReason,_that.billingKind,_that.guide,_that.performance,_that.evaluations,_that.recentEvaluations);case _:
  return null;

}
}

}

/// @nodoc


class _DelegationModelReadHeader implements DelegationModelReadHeader {
  const _DelegationModelReadHeader({required this.scope, required this.target, required this.accountName, required this.descriptor, required this.available, required this.unavailableReason, required this.billingKind, required this.guide, required this.performance, required this.evaluations, required this.recentEvaluations});


@override final  ProductReadScopeIdentity scope;
@override final  DelegationModelReadTarget target;
@override final  ReadText accountName;
@override final  ModelDescriptorRead descriptor;
@override final  bool available;
@override final  ReadText? unavailableReason;
@override final  BillingKind billingKind;
@override final  ModelSelectionGuideRead? guide;
@override final  LocalModelPerformanceSummary performance;
@override final  AgentEvaluationSummary evaluations;
@override final  TypedListRef recentEvaluations;

/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DelegationModelReadHeaderCopyWith<_DelegationModelReadHeader> get copyWith => __$DelegationModelReadHeaderCopyWithImpl<_DelegationModelReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DelegationModelReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.target, target) || other.target == target)&&(identical(other.accountName, accountName) || other.accountName == accountName)&&(identical(other.descriptor, descriptor) || other.descriptor == descriptor)&&(identical(other.available, available) || other.available == available)&&(identical(other.unavailableReason, unavailableReason) || other.unavailableReason == unavailableReason)&&(identical(other.billingKind, billingKind) || other.billingKind == billingKind)&&(identical(other.guide, guide) || other.guide == guide)&&(identical(other.performance, performance) || other.performance == performance)&&(identical(other.evaluations, evaluations) || other.evaluations == evaluations)&&(identical(other.recentEvaluations, recentEvaluations) || other.recentEvaluations == recentEvaluations));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,target,accountName,descriptor,available,unavailableReason,billingKind,guide,performance,evaluations,recentEvaluations);
}



}

/// @nodoc
abstract mixin class _$DelegationModelReadHeaderCopyWith<$Res> implements $DelegationModelReadHeaderCopyWith<$Res> {
  factory _$DelegationModelReadHeaderCopyWith(_DelegationModelReadHeader value, $Res Function(_DelegationModelReadHeader) _then) = __$DelegationModelReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ProductReadScopeIdentity scope, DelegationModelReadTarget target, ReadText accountName, ModelDescriptorRead descriptor, bool available, ReadText? unavailableReason, BillingKind billingKind, ModelSelectionGuideRead? guide, LocalModelPerformanceSummary performance, AgentEvaluationSummary evaluations, TypedListRef recentEvaluations
});


@override $ProductReadScopeIdentityCopyWith<$Res> get scope;@override $DelegationModelReadTargetCopyWith<$Res> get target;@override $ReadTextCopyWith<$Res> get accountName;@override $ModelDescriptorReadCopyWith<$Res> get descriptor;@override $ReadTextCopyWith<$Res>? get unavailableReason;@override $ModelSelectionGuideReadCopyWith<$Res>? get guide;@override $LocalModelPerformanceSummaryCopyWith<$Res> get performance;@override $AgentEvaluationSummaryCopyWith<$Res> get evaluations;@override $TypedListRefCopyWith<$Res> get recentEvaluations;

}
/// @nodoc
class __$DelegationModelReadHeaderCopyWithImpl<$Res>
    implements _$DelegationModelReadHeaderCopyWith<$Res> {
  __$DelegationModelReadHeaderCopyWithImpl(this._self, this._then);

  final _DelegationModelReadHeader _self;
  final $Res Function(_DelegationModelReadHeader) _then;

/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? target = null,Object? accountName = null,Object? descriptor = null,Object? available = null,Object? unavailableReason = freezed,Object? billingKind = null,Object? guide = freezed,Object? performance = null,Object? evaluations = null,Object? recentEvaluations = null,}) {
  return _then(_DelegationModelReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ProductReadScopeIdentity,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as DelegationModelReadTarget,accountName: null == accountName ? _self.accountName : accountName // ignore: cast_nullable_to_non_nullable
as ReadText,descriptor: null == descriptor ? _self.descriptor : descriptor // ignore: cast_nullable_to_non_nullable
as ModelDescriptorRead,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,unavailableReason: freezed == unavailableReason ? _self.unavailableReason : unavailableReason // ignore: cast_nullable_to_non_nullable
as ReadText?,billingKind: null == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind,guide: freezed == guide ? _self.guide : guide // ignore: cast_nullable_to_non_nullable
as ModelSelectionGuideRead?,performance: null == performance ? _self.performance : performance // ignore: cast_nullable_to_non_nullable
as LocalModelPerformanceSummary,evaluations: null == evaluations ? _self.evaluations : evaluations // ignore: cast_nullable_to_non_nullable
as AgentEvaluationSummary,recentEvaluations: null == recentEvaluations ? _self.recentEvaluations : recentEvaluations // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadScopeIdentityCopyWith<$Res> get scope {

  return $ProductReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationModelReadTargetCopyWith<$Res> get target {

  return $DelegationModelReadTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountName {

  return $ReadTextCopyWith<$Res>(_self.accountName, (value) {
    return _then(_self.copyWith(accountName: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelDescriptorReadCopyWith<$Res> get descriptor {

  return $ModelDescriptorReadCopyWith<$Res>(_self.descriptor, (value) {
    return _then(_self.copyWith(descriptor: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get unavailableReason {
    if (_self.unavailableReason == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.unavailableReason!, (value) {
    return _then(_self.copyWith(unavailableReason: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionGuideReadCopyWith<$Res>? get guide {
    if (_self.guide == null) {
    return null;
  }

  return $ModelSelectionGuideReadCopyWith<$Res>(_self.guide!, (value) {
    return _then(_self.copyWith(guide: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LocalModelPerformanceSummaryCopyWith<$Res> get performance {

  return $LocalModelPerformanceSummaryCopyWith<$Res>(_self.performance, (value) {
    return _then(_self.copyWith(performance: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentEvaluationSummaryCopyWith<$Res> get evaluations {

  return $AgentEvaluationSummaryCopyWith<$Res>(_self.evaluations, (value) {
    return _then(_self.copyWith(evaluations: value));
  });
}/// Create a copy of DelegationModelReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get recentEvaluations {

  return $TypedListRefCopyWith<$Res>(_self.recentEvaluations, (value) {
    return _then(_self.copyWith(recentEvaluations: value));
  });
}
}

/// @nodoc
mixin _$ModelSelectionGuideRead {


/// Create a copy of ModelSelectionGuideRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelSelectionGuideReadCopyWith<ModelSelectionGuideRead> get copyWith => _$ModelSelectionGuideReadCopyWithImpl<ModelSelectionGuideRead>(this as ModelSelectionGuideRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelSelectionGuideRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelSelectionGuideRead&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&const DeepCollectionEquality().equals(other.taskSuitability, _this.taskSuitability)&&(identical(other.limitations, _this.limitations) || other.limitations == _this.limitations)&&(identical(other.sources, _this.sources) || other.sources == _this.sources));
}


@override
int get hashCode {
  final _this = this as ModelSelectionGuideRead;
  return Object.hash(runtimeType,_this.summary,const DeepCollectionEquality().hash(_this.taskSuitability),_this.limitations,_this.sources);
}



}

/// @nodoc
abstract mixin class $ModelSelectionGuideReadCopyWith<$Res>  {
  factory $ModelSelectionGuideReadCopyWith(ModelSelectionGuideRead value, $Res Function(ModelSelectionGuideRead) _then) = _$ModelSelectionGuideReadCopyWithImpl;
@useResult
$Res call({
 ReadText summary, List<AgentTaskCategory> taskSuitability, TypedListRef limitations, TypedListRef sources
});


$ReadTextCopyWith<$Res> get summary;$TypedListRefCopyWith<$Res> get limitations;$TypedListRefCopyWith<$Res> get sources;

}
/// @nodoc
class _$ModelSelectionGuideReadCopyWithImpl<$Res>
    implements $ModelSelectionGuideReadCopyWith<$Res> {
  _$ModelSelectionGuideReadCopyWithImpl(this._self, this._then);

  final ModelSelectionGuideRead _self;
  final $Res Function(ModelSelectionGuideRead) _then;

/// Create a copy of ModelSelectionGuideRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? summary = null,Object? taskSuitability = null,Object? limitations = null,Object? sources = null,}) {
  return _then(ModelSelectionGuideRead(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText,taskSuitability: null == taskSuitability ? _self.taskSuitability : taskSuitability // ignore: cast_nullable_to_non_nullable
as List<AgentTaskCategory>,limitations: null == limitations ? _self.limitations : limitations // ignore: cast_nullable_to_non_nullable
as TypedListRef,sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of ModelSelectionGuideRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get summary {

  return $ReadTextCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of ModelSelectionGuideRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get limitations {

  return $TypedListRefCopyWith<$Res>(_self.limitations, (value) {
    return _then(_self.copyWith(limitations: value));
  });
}/// Create a copy of ModelSelectionGuideRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get sources {

  return $TypedListRefCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelSelectionGuideRead].
extension ModelSelectionGuideReadPatterns on ModelSelectionGuideRead {
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
mixin _$ModelSelectionSourceRead {

 ModelSelectionSourceKind get kind; ReadText get url; int get verifiedAt; ModelSelectionMeasurementRead? get measurement;
/// Create a copy of ModelSelectionSourceRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelSelectionSourceReadCopyWith<ModelSelectionSourceRead> get copyWith => _$ModelSelectionSourceReadCopyWithImpl<ModelSelectionSourceRead>(this as ModelSelectionSourceRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelSelectionSourceRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelSelectionSourceRead&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.verifiedAt, _this.verifiedAt) || other.verifiedAt == _this.verifiedAt)&&(identical(other.measurement, _this.measurement) || other.measurement == _this.measurement));
}


@override
int get hashCode {
  final _this = this as ModelSelectionSourceRead;
  return Object.hash(runtimeType,_this.kind,_this.url,_this.verifiedAt,_this.measurement);
}



}

/// @nodoc
abstract mixin class $ModelSelectionSourceReadCopyWith<$Res>  {
  factory $ModelSelectionSourceReadCopyWith(ModelSelectionSourceRead value, $Res Function(ModelSelectionSourceRead) _then) = _$ModelSelectionSourceReadCopyWithImpl;
@useResult
$Res call({
 ModelSelectionSourceKind kind, ReadText url, int verifiedAt, ModelSelectionMeasurementRead? measurement
});


$ReadTextCopyWith<$Res> get url;$ModelSelectionMeasurementReadCopyWith<$Res>? get measurement;

}
/// @nodoc
class _$ModelSelectionSourceReadCopyWithImpl<$Res>
    implements $ModelSelectionSourceReadCopyWith<$Res> {
  _$ModelSelectionSourceReadCopyWithImpl(this._self, this._then);

  final ModelSelectionSourceRead _self;
  final $Res Function(ModelSelectionSourceRead) _then;

/// Create a copy of ModelSelectionSourceRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? url = null,Object? verifiedAt = null,Object? measurement = freezed,}) {
  return _then(ModelSelectionSourceRead(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ModelSelectionSourceKind,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as ReadText,verifiedAt: null == verifiedAt ? _self.verifiedAt : verifiedAt // ignore: cast_nullable_to_non_nullable
as int,measurement: freezed == measurement ? _self.measurement : measurement // ignore: cast_nullable_to_non_nullable
as ModelSelectionMeasurementRead?,
  ));
}
/// Create a copy of ModelSelectionSourceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get url {

  return $ReadTextCopyWith<$Res>(_self.url, (value) {
    return _then(_self.copyWith(url: value));
  });
}/// Create a copy of ModelSelectionSourceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionMeasurementReadCopyWith<$Res>? get measurement {
    if (_self.measurement == null) {
    return null;
  }

  return $ModelSelectionMeasurementReadCopyWith<$Res>(_self.measurement!, (value) {
    return _then(_self.copyWith(measurement: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelSelectionSourceRead].
extension ModelSelectionSourceReadPatterns on ModelSelectionSourceRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelSelectionSourceRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelSelectionSourceRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelSelectionSourceRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelSelectionSourceRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelSelectionSourceRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelSelectionSourceRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModelSelectionSourceKind kind,  ReadText url,  int verifiedAt,  ModelSelectionMeasurementRead? measurement)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelSelectionSourceRead() when $default != null:
return $default(_that.kind,_that.url,_that.verifiedAt,_that.measurement);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModelSelectionSourceKind kind,  ReadText url,  int verifiedAt,  ModelSelectionMeasurementRead? measurement)  $default,) {final _that = this;
switch (_that) {
case _ModelSelectionSourceRead():
return $default(_that.kind,_that.url,_that.verifiedAt,_that.measurement);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModelSelectionSourceKind kind,  ReadText url,  int verifiedAt,  ModelSelectionMeasurementRead? measurement)?  $default,) {final _that = this;
switch (_that) {
case _ModelSelectionSourceRead() when $default != null:
return $default(_that.kind,_that.url,_that.verifiedAt,_that.measurement);case _:
  return null;

}
}

}

/// @nodoc


class _ModelSelectionSourceRead implements ModelSelectionSourceRead {
  const _ModelSelectionSourceRead({required this.kind, required this.url, required this.verifiedAt, required this.measurement});


@override final  ModelSelectionSourceKind kind;
@override final  ReadText url;
@override final  int verifiedAt;
@override final  ModelSelectionMeasurementRead? measurement;

/// Create a copy of ModelSelectionSourceRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelSelectionSourceReadCopyWith<_ModelSelectionSourceRead> get copyWith => __$ModelSelectionSourceReadCopyWithImpl<_ModelSelectionSourceRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelSelectionSourceRead&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.url, url) || other.url == url)&&(identical(other.verifiedAt, verifiedAt) || other.verifiedAt == verifiedAt)&&(identical(other.measurement, measurement) || other.measurement == measurement));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,url,verifiedAt,measurement);
}



}

/// @nodoc
abstract mixin class _$ModelSelectionSourceReadCopyWith<$Res> implements $ModelSelectionSourceReadCopyWith<$Res> {
  factory _$ModelSelectionSourceReadCopyWith(_ModelSelectionSourceRead value, $Res Function(_ModelSelectionSourceRead) _then) = __$ModelSelectionSourceReadCopyWithImpl;
@override @useResult
$Res call({
 ModelSelectionSourceKind kind, ReadText url, int verifiedAt, ModelSelectionMeasurementRead? measurement
});


@override $ReadTextCopyWith<$Res> get url;@override $ModelSelectionMeasurementReadCopyWith<$Res>? get measurement;

}
/// @nodoc
class __$ModelSelectionSourceReadCopyWithImpl<$Res>
    implements _$ModelSelectionSourceReadCopyWith<$Res> {
  __$ModelSelectionSourceReadCopyWithImpl(this._self, this._then);

  final _ModelSelectionSourceRead _self;
  final $Res Function(_ModelSelectionSourceRead) _then;

/// Create a copy of ModelSelectionSourceRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? url = null,Object? verifiedAt = null,Object? measurement = freezed,}) {
  return _then(_ModelSelectionSourceRead(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ModelSelectionSourceKind,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as ReadText,verifiedAt: null == verifiedAt ? _self.verifiedAt : verifiedAt // ignore: cast_nullable_to_non_nullable
as int,measurement: freezed == measurement ? _self.measurement : measurement // ignore: cast_nullable_to_non_nullable
as ModelSelectionMeasurementRead?,
  ));
}

/// Create a copy of ModelSelectionSourceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get url {

  return $ReadTextCopyWith<$Res>(_self.url, (value) {
    return _then(_self.copyWith(url: value));
  });
}/// Create a copy of ModelSelectionSourceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionMeasurementReadCopyWith<$Res>? get measurement {
    if (_self.measurement == null) {
    return null;
  }

  return $ModelSelectionMeasurementReadCopyWith<$Res>(_self.measurement!, (value) {
    return _then(_self.copyWith(measurement: value));
  });
}
}

/// @nodoc
mixin _$ModelSelectionMeasurementRead {

 ReadText get model; ReadText? get effort; ReadText get metric; ReadText? get metricVersion; double? get score;
/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelSelectionMeasurementReadCopyWith<ModelSelectionMeasurementRead> get copyWith => _$ModelSelectionMeasurementReadCopyWithImpl<ModelSelectionMeasurementRead>(this as ModelSelectionMeasurementRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelSelectionMeasurementRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelSelectionMeasurementRead&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.metric, _this.metric) || other.metric == _this.metric)&&(identical(other.metricVersion, _this.metricVersion) || other.metricVersion == _this.metricVersion)&&(identical(other.score, _this.score) || other.score == _this.score));
}


@override
int get hashCode {
  final _this = this as ModelSelectionMeasurementRead;
  return Object.hash(runtimeType,_this.model,_this.effort,_this.metric,_this.metricVersion,_this.score);
}



}

/// @nodoc
abstract mixin class $ModelSelectionMeasurementReadCopyWith<$Res>  {
  factory $ModelSelectionMeasurementReadCopyWith(ModelSelectionMeasurementRead value, $Res Function(ModelSelectionMeasurementRead) _then) = _$ModelSelectionMeasurementReadCopyWithImpl;
@useResult
$Res call({
 ReadText model, ReadText? effort, ReadText metric, ReadText? metricVersion, double? score
});


$ReadTextCopyWith<$Res> get model;$ReadTextCopyWith<$Res>? get effort;$ReadTextCopyWith<$Res> get metric;$ReadTextCopyWith<$Res>? get metricVersion;

}
/// @nodoc
class _$ModelSelectionMeasurementReadCopyWithImpl<$Res>
    implements $ModelSelectionMeasurementReadCopyWith<$Res> {
  _$ModelSelectionMeasurementReadCopyWithImpl(this._self, this._then);

  final ModelSelectionMeasurementRead _self;
  final $Res Function(ModelSelectionMeasurementRead) _then;

/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? model = null,Object? effort = freezed,Object? metric = null,Object? metricVersion = freezed,Object? score = freezed,}) {
  return _then(ModelSelectionMeasurementRead(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,metric: null == metric ? _self.metric : metric // ignore: cast_nullable_to_non_nullable
as ReadText,metricVersion: freezed == metricVersion ? _self.metricVersion : metricVersion // ignore: cast_nullable_to_non_nullable
as ReadText?,score: freezed == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}
/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get model {

  return $ReadTextCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get metric {

  return $ReadTextCopyWith<$Res>(_self.metric, (value) {
    return _then(_self.copyWith(metric: value));
  });
}/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get metricVersion {
    if (_self.metricVersion == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.metricVersion!, (value) {
    return _then(_self.copyWith(metricVersion: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelSelectionMeasurementRead].
extension ModelSelectionMeasurementReadPatterns on ModelSelectionMeasurementRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelSelectionMeasurementRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelSelectionMeasurementRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelSelectionMeasurementRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelSelectionMeasurementRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelSelectionMeasurementRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelSelectionMeasurementRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText model,  ReadText? effort,  ReadText metric,  ReadText? metricVersion,  double? score)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelSelectionMeasurementRead() when $default != null:
return $default(_that.model,_that.effort,_that.metric,_that.metricVersion,_that.score);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText model,  ReadText? effort,  ReadText metric,  ReadText? metricVersion,  double? score)  $default,) {final _that = this;
switch (_that) {
case _ModelSelectionMeasurementRead():
return $default(_that.model,_that.effort,_that.metric,_that.metricVersion,_that.score);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText model,  ReadText? effort,  ReadText metric,  ReadText? metricVersion,  double? score)?  $default,) {final _that = this;
switch (_that) {
case _ModelSelectionMeasurementRead() when $default != null:
return $default(_that.model,_that.effort,_that.metric,_that.metricVersion,_that.score);case _:
  return null;

}
}

}

/// @nodoc


class _ModelSelectionMeasurementRead implements ModelSelectionMeasurementRead {
  const _ModelSelectionMeasurementRead({required this.model, required this.effort, required this.metric, required this.metricVersion, required this.score});


@override final  ReadText model;
@override final  ReadText? effort;
@override final  ReadText metric;
@override final  ReadText? metricVersion;
@override final  double? score;

/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelSelectionMeasurementReadCopyWith<_ModelSelectionMeasurementRead> get copyWith => __$ModelSelectionMeasurementReadCopyWithImpl<_ModelSelectionMeasurementRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelSelectionMeasurementRead&&(identical(other.model, model) || other.model == model)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.metric, metric) || other.metric == metric)&&(identical(other.metricVersion, metricVersion) || other.metricVersion == metricVersion)&&(identical(other.score, score) || other.score == score));
}


@override
int get hashCode {
    return Object.hash(runtimeType,model,effort,metric,metricVersion,score);
}



}

/// @nodoc
abstract mixin class _$ModelSelectionMeasurementReadCopyWith<$Res> implements $ModelSelectionMeasurementReadCopyWith<$Res> {
  factory _$ModelSelectionMeasurementReadCopyWith(_ModelSelectionMeasurementRead value, $Res Function(_ModelSelectionMeasurementRead) _then) = __$ModelSelectionMeasurementReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText model, ReadText? effort, ReadText metric, ReadText? metricVersion, double? score
});


@override $ReadTextCopyWith<$Res> get model;@override $ReadTextCopyWith<$Res>? get effort;@override $ReadTextCopyWith<$Res> get metric;@override $ReadTextCopyWith<$Res>? get metricVersion;

}
/// @nodoc
class __$ModelSelectionMeasurementReadCopyWithImpl<$Res>
    implements _$ModelSelectionMeasurementReadCopyWith<$Res> {
  __$ModelSelectionMeasurementReadCopyWithImpl(this._self, this._then);

  final _ModelSelectionMeasurementRead _self;
  final $Res Function(_ModelSelectionMeasurementRead) _then;

/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? model = null,Object? effort = freezed,Object? metric = null,Object? metricVersion = freezed,Object? score = freezed,}) {
  return _then(_ModelSelectionMeasurementRead(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,metric: null == metric ? _self.metric : metric // ignore: cast_nullable_to_non_nullable
as ReadText,metricVersion: freezed == metricVersion ? _self.metricVersion : metricVersion // ignore: cast_nullable_to_non_nullable
as ReadText?,score: freezed == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get model {

  return $ReadTextCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get metric {

  return $ReadTextCopyWith<$Res>(_self.metric, (value) {
    return _then(_self.copyWith(metric: value));
  });
}/// Create a copy of ModelSelectionMeasurementRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get metricVersion {
    if (_self.metricVersion == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.metricVersion!, (value) {
    return _then(_self.copyWith(metricVersion: value));
  });
}
}

/// @nodoc
mixin _$AgentEvaluationRead {

 ReadText get agentId; ReadText get parentAgentId; ReadText get accountId; ReadText get modelId; ReadText? get effort; ReadText get profileId; DelegationMode get mode; DelegationPreference get preference; ReadText get turnId; int get revision; AgentTaskCategory get taskCategory; AgentEvaluationOutcome get outcome; int? get quality; int? get instructionFollowing; ReadText get comment; int get createdAt; int get updatedAt;
/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentEvaluationReadCopyWith<AgentEvaluationRead> get copyWith => _$AgentEvaluationReadCopyWithImpl<AgentEvaluationRead>(this as AgentEvaluationRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentEvaluationRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentEvaluationRead&&(identical(other.agentId, _this.agentId) || other.agentId == _this.agentId)&&(identical(other.parentAgentId, _this.parentAgentId) || other.parentAgentId == _this.parentAgentId)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.preference, _this.preference) || other.preference == _this.preference)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.taskCategory, _this.taskCategory) || other.taskCategory == _this.taskCategory)&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome)&&(identical(other.quality, _this.quality) || other.quality == _this.quality)&&(identical(other.instructionFollowing, _this.instructionFollowing) || other.instructionFollowing == _this.instructionFollowing)&&(identical(other.comment, _this.comment) || other.comment == _this.comment)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as AgentEvaluationRead;
  return Object.hash(runtimeType,_this.agentId,_this.parentAgentId,_this.accountId,_this.modelId,_this.effort,_this.profileId,_this.mode,_this.preference,_this.turnId,_this.revision,_this.taskCategory,_this.outcome,_this.quality,_this.instructionFollowing,_this.comment,_this.createdAt,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $AgentEvaluationReadCopyWith<$Res>  {
  factory $AgentEvaluationReadCopyWith(AgentEvaluationRead value, $Res Function(AgentEvaluationRead) _then) = _$AgentEvaluationReadCopyWithImpl;
@useResult
$Res call({
 ReadText agentId, ReadText parentAgentId, ReadText accountId, ReadText modelId, ReadText? effort, ReadText profileId, DelegationMode mode, DelegationPreference preference, ReadText turnId, int revision, AgentTaskCategory taskCategory, AgentEvaluationOutcome outcome, int? quality, int? instructionFollowing, ReadText comment, int createdAt, int updatedAt
});


$ReadTextCopyWith<$Res> get agentId;$ReadTextCopyWith<$Res> get parentAgentId;$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get modelId;$ReadTextCopyWith<$Res>? get effort;$ReadTextCopyWith<$Res> get profileId;$ReadTextCopyWith<$Res> get turnId;$ReadTextCopyWith<$Res> get comment;

}
/// @nodoc
class _$AgentEvaluationReadCopyWithImpl<$Res>
    implements $AgentEvaluationReadCopyWith<$Res> {
  _$AgentEvaluationReadCopyWithImpl(this._self, this._then);

  final AgentEvaluationRead _self;
  final $Res Function(AgentEvaluationRead) _then;

/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? agentId = null,Object? parentAgentId = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? profileId = null,Object? mode = null,Object? preference = null,Object? turnId = null,Object? revision = null,Object? taskCategory = null,Object? outcome = null,Object? quality = freezed,Object? instructionFollowing = freezed,Object? comment = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(AgentEvaluationRead(
agentId: null == agentId ? _self.agentId : agentId // ignore: cast_nullable_to_non_nullable
as ReadText,parentAgentId: null == parentAgentId ? _self.parentAgentId : parentAgentId // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as ReadText,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as DelegationMode,preference: null == preference ? _self.preference : preference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,taskCategory: null == taskCategory ? _self.taskCategory : taskCategory // ignore: cast_nullable_to_non_nullable
as AgentTaskCategory,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AgentEvaluationOutcome,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as int?,instructionFollowing: freezed == instructionFollowing ? _self.instructionFollowing : instructionFollowing // ignore: cast_nullable_to_non_nullable
as int?,comment: null == comment ? _self.comment : comment // ignore: cast_nullable_to_non_nullable
as ReadText,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get agentId {

  return $ReadTextCopyWith<$Res>(_self.agentId, (value) {
    return _then(_self.copyWith(agentId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get parentAgentId {

  return $ReadTextCopyWith<$Res>(_self.parentAgentId, (value) {
    return _then(_self.copyWith(parentAgentId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get profileId {

  return $ReadTextCopyWith<$Res>(_self.profileId, (value) {
    return _then(_self.copyWith(profileId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get comment {

  return $ReadTextCopyWith<$Res>(_self.comment, (value) {
    return _then(_self.copyWith(comment: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentEvaluationRead].
extension AgentEvaluationReadPatterns on AgentEvaluationRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentEvaluationRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentEvaluationRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentEvaluationRead value)  $default,){
final _that = this;
switch (_that) {
case _AgentEvaluationRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentEvaluationRead value)?  $default,){
final _that = this;
switch (_that) {
case _AgentEvaluationRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText agentId,  ReadText parentAgentId,  ReadText accountId,  ReadText modelId,  ReadText? effort,  ReadText profileId,  DelegationMode mode,  DelegationPreference preference,  ReadText turnId,  int revision,  AgentTaskCategory taskCategory,  AgentEvaluationOutcome outcome,  int? quality,  int? instructionFollowing,  ReadText comment,  int createdAt,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentEvaluationRead() when $default != null:
return $default(_that.agentId,_that.parentAgentId,_that.accountId,_that.modelId,_that.effort,_that.profileId,_that.mode,_that.preference,_that.turnId,_that.revision,_that.taskCategory,_that.outcome,_that.quality,_that.instructionFollowing,_that.comment,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText agentId,  ReadText parentAgentId,  ReadText accountId,  ReadText modelId,  ReadText? effort,  ReadText profileId,  DelegationMode mode,  DelegationPreference preference,  ReadText turnId,  int revision,  AgentTaskCategory taskCategory,  AgentEvaluationOutcome outcome,  int? quality,  int? instructionFollowing,  ReadText comment,  int createdAt,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _AgentEvaluationRead():
return $default(_that.agentId,_that.parentAgentId,_that.accountId,_that.modelId,_that.effort,_that.profileId,_that.mode,_that.preference,_that.turnId,_that.revision,_that.taskCategory,_that.outcome,_that.quality,_that.instructionFollowing,_that.comment,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText agentId,  ReadText parentAgentId,  ReadText accountId,  ReadText modelId,  ReadText? effort,  ReadText profileId,  DelegationMode mode,  DelegationPreference preference,  ReadText turnId,  int revision,  AgentTaskCategory taskCategory,  AgentEvaluationOutcome outcome,  int? quality,  int? instructionFollowing,  ReadText comment,  int createdAt,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _AgentEvaluationRead() when $default != null:
return $default(_that.agentId,_that.parentAgentId,_that.accountId,_that.modelId,_that.effort,_that.profileId,_that.mode,_that.preference,_that.turnId,_that.revision,_that.taskCategory,_that.outcome,_that.quality,_that.instructionFollowing,_that.comment,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AgentEvaluationRead implements AgentEvaluationRead {
  const _AgentEvaluationRead({required this.agentId, required this.parentAgentId, required this.accountId, required this.modelId, required this.effort, required this.profileId, required this.mode, required this.preference, required this.turnId, required this.revision, required this.taskCategory, required this.outcome, required this.quality, required this.instructionFollowing, required this.comment, required this.createdAt, required this.updatedAt});


@override final  ReadText agentId;
@override final  ReadText parentAgentId;
@override final  ReadText accountId;
@override final  ReadText modelId;
@override final  ReadText? effort;
@override final  ReadText profileId;
@override final  DelegationMode mode;
@override final  DelegationPreference preference;
@override final  ReadText turnId;
@override final  int revision;
@override final  AgentTaskCategory taskCategory;
@override final  AgentEvaluationOutcome outcome;
@override final  int? quality;
@override final  int? instructionFollowing;
@override final  ReadText comment;
@override final  int createdAt;
@override final  int updatedAt;

/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentEvaluationReadCopyWith<_AgentEvaluationRead> get copyWith => __$AgentEvaluationReadCopyWithImpl<_AgentEvaluationRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentEvaluationRead&&(identical(other.agentId, agentId) || other.agentId == agentId)&&(identical(other.parentAgentId, parentAgentId) || other.parentAgentId == parentAgentId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.preference, preference) || other.preference == preference)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.taskCategory, taskCategory) || other.taskCategory == taskCategory)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.instructionFollowing, instructionFollowing) || other.instructionFollowing == instructionFollowing)&&(identical(other.comment, comment) || other.comment == comment)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,agentId,parentAgentId,accountId,modelId,effort,profileId,mode,preference,turnId,revision,taskCategory,outcome,quality,instructionFollowing,comment,createdAt,updatedAt);
}



}

/// @nodoc
abstract mixin class _$AgentEvaluationReadCopyWith<$Res> implements $AgentEvaluationReadCopyWith<$Res> {
  factory _$AgentEvaluationReadCopyWith(_AgentEvaluationRead value, $Res Function(_AgentEvaluationRead) _then) = __$AgentEvaluationReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText agentId, ReadText parentAgentId, ReadText accountId, ReadText modelId, ReadText? effort, ReadText profileId, DelegationMode mode, DelegationPreference preference, ReadText turnId, int revision, AgentTaskCategory taskCategory, AgentEvaluationOutcome outcome, int? quality, int? instructionFollowing, ReadText comment, int createdAt, int updatedAt
});


@override $ReadTextCopyWith<$Res> get agentId;@override $ReadTextCopyWith<$Res> get parentAgentId;@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get modelId;@override $ReadTextCopyWith<$Res>? get effort;@override $ReadTextCopyWith<$Res> get profileId;@override $ReadTextCopyWith<$Res> get turnId;@override $ReadTextCopyWith<$Res> get comment;

}
/// @nodoc
class __$AgentEvaluationReadCopyWithImpl<$Res>
    implements _$AgentEvaluationReadCopyWith<$Res> {
  __$AgentEvaluationReadCopyWithImpl(this._self, this._then);

  final _AgentEvaluationRead _self;
  final $Res Function(_AgentEvaluationRead) _then;

/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? agentId = null,Object? parentAgentId = null,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? profileId = null,Object? mode = null,Object? preference = null,Object? turnId = null,Object? revision = null,Object? taskCategory = null,Object? outcome = null,Object? quality = freezed,Object? instructionFollowing = freezed,Object? comment = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_AgentEvaluationRead(
agentId: null == agentId ? _self.agentId : agentId // ignore: cast_nullable_to_non_nullable
as ReadText,parentAgentId: null == parentAgentId ? _self.parentAgentId : parentAgentId // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as ReadText,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as DelegationMode,preference: null == preference ? _self.preference : preference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,taskCategory: null == taskCategory ? _self.taskCategory : taskCategory // ignore: cast_nullable_to_non_nullable
as AgentTaskCategory,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AgentEvaluationOutcome,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as int?,instructionFollowing: freezed == instructionFollowing ? _self.instructionFollowing : instructionFollowing // ignore: cast_nullable_to_non_nullable
as int?,comment: null == comment ? _self.comment : comment // ignore: cast_nullable_to_non_nullable
as ReadText,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get agentId {

  return $ReadTextCopyWith<$Res>(_self.agentId, (value) {
    return _then(_self.copyWith(agentId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get parentAgentId {

  return $ReadTextCopyWith<$Res>(_self.parentAgentId, (value) {
    return _then(_self.copyWith(parentAgentId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get profileId {

  return $ReadTextCopyWith<$Res>(_self.profileId, (value) {
    return _then(_self.copyWith(profileId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of AgentEvaluationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get comment {

  return $ReadTextCopyWith<$Res>(_self.comment, (value) {
    return _then(_self.copyWith(comment: value));
  });
}
}

/// @nodoc
mixin _$ModelSelectionSourceReadPage {


/// Create a copy of ModelSelectionSourceReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelSelectionSourceReadPageCopyWith<ModelSelectionSourceReadPage> get copyWith => _$ModelSelectionSourceReadPageCopyWithImpl<ModelSelectionSourceReadPage>(this as ModelSelectionSourceReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelSelectionSourceReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelSelectionSourceReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as ModelSelectionSourceReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $ModelSelectionSourceReadPageCopyWith<$Res>  {
  factory $ModelSelectionSourceReadPageCopyWith(ModelSelectionSourceReadPage value, $Res Function(ModelSelectionSourceReadPage) _then) = _$ModelSelectionSourceReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<ModelSelectionSourceRead> items, int? nextOffset
});




}
/// @nodoc
class _$ModelSelectionSourceReadPageCopyWithImpl<$Res>
    implements $ModelSelectionSourceReadPageCopyWith<$Res> {
  _$ModelSelectionSourceReadPageCopyWithImpl(this._self, this._then);

  final ModelSelectionSourceReadPage _self;
  final $Res Function(ModelSelectionSourceReadPage) _then;

/// Create a copy of ModelSelectionSourceReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(ModelSelectionSourceReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ModelSelectionSourceRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelSelectionSourceReadPage].
extension ModelSelectionSourceReadPagePatterns on ModelSelectionSourceReadPage {
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
mixin _$AgentEvaluationReadPage {


/// Create a copy of AgentEvaluationReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentEvaluationReadPageCopyWith<AgentEvaluationReadPage> get copyWith => _$AgentEvaluationReadPageCopyWithImpl<AgentEvaluationReadPage>(this as AgentEvaluationReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentEvaluationReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentEvaluationReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as AgentEvaluationReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $AgentEvaluationReadPageCopyWith<$Res>  {
  factory $AgentEvaluationReadPageCopyWith(AgentEvaluationReadPage value, $Res Function(AgentEvaluationReadPage) _then) = _$AgentEvaluationReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<AgentEvaluationRead> items, int? nextOffset
});




}
/// @nodoc
class _$AgentEvaluationReadPageCopyWithImpl<$Res>
    implements $AgentEvaluationReadPageCopyWith<$Res> {
  _$AgentEvaluationReadPageCopyWithImpl(this._self, this._then);

  final AgentEvaluationReadPage _self;
  final $Res Function(AgentEvaluationReadPage) _then;

/// Create a copy of AgentEvaluationReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(AgentEvaluationReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<AgentEvaluationRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentEvaluationReadPage].
extension AgentEvaluationReadPagePatterns on AgentEvaluationReadPage {
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
