// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'delegation_model_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ListDelegationModelsRequest {


/// Create a copy of ListDelegationModelsRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ListDelegationModelsRequestCopyWith<ListDelegationModelsRequest> get copyWith => _$ListDelegationModelsRequestCopyWithImpl<ListDelegationModelsRequest>(this as ListDelegationModelsRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ListDelegationModelsRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ListDelegationModelsRequest&&const DeepCollectionEquality().equals(other.capabilities, _this.capabilities)&&(identical(other.taskCategory, _this.taskCategory) || other.taskCategory == _this.taskCategory)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.billingKind, _this.billingKind) || other.billingKind == _this.billingKind)&&(identical(other.minContextWindow, _this.minContextWindow) || other.minContextWindow == _this.minContextWindow)&&(identical(other.limit, _this.limit) || other.limit == _this.limit)&&(identical(other.cursor, _this.cursor) || other.cursor == _this.cursor));
}


@override
int get hashCode {
  final _this = this as ListDelegationModelsRequest;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.capabilities),_this.taskCategory,_this.accountId,_this.billingKind,_this.minContextWindow,_this.limit,_this.cursor);
}

@override
String toString() {
  final _this = this as ListDelegationModelsRequest;
  return 'ListDelegationModelsRequest(capabilities: ${_this.capabilities}, taskCategory: ${_this.taskCategory}, accountId: ${_this.accountId}, billingKind: ${_this.billingKind}, minContextWindow: ${_this.minContextWindow}, limit: ${_this.limit}, cursor: ${_this.cursor})';
}


}

/// @nodoc
abstract mixin class $ListDelegationModelsRequestCopyWith<$Res>  {
  factory $ListDelegationModelsRequestCopyWith(ListDelegationModelsRequest value, $Res Function(ListDelegationModelsRequest) _then) = _$ListDelegationModelsRequestCopyWithImpl;
@useResult
$Res call({
 List<DelegationModelCapability> capabilities, AgentTaskCategory? taskCategory, String? accountId, BillingKind? billingKind, int? minContextWindow, int? limit, String? cursor
});




}
/// @nodoc
class _$ListDelegationModelsRequestCopyWithImpl<$Res>
    implements $ListDelegationModelsRequestCopyWith<$Res> {
  _$ListDelegationModelsRequestCopyWithImpl(this._self, this._then);

  final ListDelegationModelsRequest _self;
  final $Res Function(ListDelegationModelsRequest) _then;

/// Create a copy of ListDelegationModelsRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? capabilities = null,Object? taskCategory = freezed,Object? accountId = freezed,Object? billingKind = freezed,Object? minContextWindow = freezed,Object? limit = freezed,Object? cursor = freezed,}) {
  return _then(ListDelegationModelsRequest(
capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as List<DelegationModelCapability>,taskCategory: freezed == taskCategory ? _self.taskCategory : taskCategory // ignore: cast_nullable_to_non_nullable
as AgentTaskCategory?,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,billingKind: freezed == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind?,minContextWindow: freezed == minContextWindow ? _self.minContextWindow : minContextWindow // ignore: cast_nullable_to_non_nullable
as int?,limit: freezed == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int?,cursor: freezed == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ListDelegationModelsRequest].
extension ListDelegationModelsRequestPatterns on ListDelegationModelsRequest {
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
mixin _$DelegationModelList {


/// Create a copy of DelegationModelList
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DelegationModelListCopyWith<DelegationModelList> get copyWith => _$DelegationModelListCopyWithImpl<DelegationModelList>(this as DelegationModelList, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DelegationModelList;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DelegationModelList&&const DeepCollectionEquality().equals(other.models, _this.models)&&(identical(other.catalogRevision, _this.catalogRevision) || other.catalogRevision == _this.catalogRevision)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor));
}


@override
int get hashCode {
  final _this = this as DelegationModelList;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.models),_this.catalogRevision,_this.nextCursor);
}



}

/// @nodoc
abstract mixin class $DelegationModelListCopyWith<$Res>  {
  factory $DelegationModelListCopyWith(DelegationModelList value, $Res Function(DelegationModelList) _then) = _$DelegationModelListCopyWithImpl;
@useResult
$Res call({
 List<DelegationModelListItem> models, int catalogRevision, String? nextCursor
});




}
/// @nodoc
class _$DelegationModelListCopyWithImpl<$Res>
    implements $DelegationModelListCopyWith<$Res> {
  _$DelegationModelListCopyWithImpl(this._self, this._then);

  final DelegationModelList _self;
  final $Res Function(DelegationModelList) _then;

/// Create a copy of DelegationModelList
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? models = null,Object? catalogRevision = null,Object? nextCursor = freezed,}) {
  return _then(DelegationModelList(
models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as List<DelegationModelListItem>,catalogRevision: null == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [DelegationModelList].
extension DelegationModelListPatterns on DelegationModelList {
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
mixin _$DelegationModelListItem {


/// Create a copy of DelegationModelListItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DelegationModelListItemCopyWith<DelegationModelListItem> get copyWith => _$DelegationModelListItemCopyWithImpl<DelegationModelListItem>(this as DelegationModelListItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DelegationModelListItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DelegationModelListItem&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.accountName, _this.accountName) || other.accountName == _this.accountName)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&const DeepCollectionEquality().equals(other.taskSuitability, _this.taskSuitability)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.capabilities, _this.capabilities) || other.capabilities == _this.capabilities)&&const DeepCollectionEquality().equals(other.reasoningEfforts, _this.reasoningEfforts)&&(identical(other.pricing, _this.pricing) || other.pricing == _this.pricing)&&(identical(other.billingKind, _this.billingKind) || other.billingKind == _this.billingKind)&&(identical(other.performance, _this.performance) || other.performance == _this.performance)&&(identical(other.evaluations, _this.evaluations) || other.evaluations == _this.evaluations));
}


@override
int get hashCode {
  final _this = this as DelegationModelListItem;
  return Object.hash(runtimeType,_this.key,_this.accountName,_this.displayName,_this.summary,const DeepCollectionEquality().hash(_this.taskSuitability),_this.contextWindow,_this.capabilities,const DeepCollectionEquality().hash(_this.reasoningEfforts),_this.pricing,_this.billingKind,_this.performance,_this.evaluations);
}



}

/// @nodoc
abstract mixin class $DelegationModelListItemCopyWith<$Res>  {
  factory $DelegationModelListItemCopyWith(DelegationModelListItem value, $Res Function(DelegationModelListItem) _then) = _$DelegationModelListItemCopyWithImpl;
@useResult
$Res call({
 AccountModelKey key, String accountName, String displayName, String? summary, List<AgentTaskCategory> taskSuitability, int? contextWindow, ModelCapabilities capabilities, List<String> reasoningEfforts, ModelPricing? pricing, BillingKind billingKind, LocalModelPerformanceSummary performance, AgentEvaluationSummary evaluations
});


$AccountModelKeyCopyWith<$Res> get key;$ModelCapabilitiesCopyWith<$Res> get capabilities;$ModelPricingCopyWith<$Res>? get pricing;$LocalModelPerformanceSummaryCopyWith<$Res> get performance;$AgentEvaluationSummaryCopyWith<$Res> get evaluations;

}
/// @nodoc
class _$DelegationModelListItemCopyWithImpl<$Res>
    implements $DelegationModelListItemCopyWith<$Res> {
  _$DelegationModelListItemCopyWithImpl(this._self, this._then);

  final DelegationModelListItem _self;
  final $Res Function(DelegationModelListItem) _then;

/// Create a copy of DelegationModelListItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? accountName = null,Object? displayName = null,Object? summary = freezed,Object? taskSuitability = null,Object? contextWindow = freezed,Object? capabilities = null,Object? reasoningEfforts = null,Object? pricing = freezed,Object? billingKind = null,Object? performance = null,Object? evaluations = null,}) {
  return _then(DelegationModelListItem(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountModelKey,accountName: null == accountName ? _self.accountName : accountName // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,taskSuitability: null == taskSuitability ? _self.taskSuitability : taskSuitability // ignore: cast_nullable_to_non_nullable
as List<AgentTaskCategory>,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as ModelCapabilities,reasoningEfforts: null == reasoningEfforts ? _self.reasoningEfforts : reasoningEfforts // ignore: cast_nullable_to_non_nullable
as List<String>,pricing: freezed == pricing ? _self.pricing : pricing // ignore: cast_nullable_to_non_nullable
as ModelPricing?,billingKind: null == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind,performance: null == performance ? _self.performance : performance // ignore: cast_nullable_to_non_nullable
as LocalModelPerformanceSummary,evaluations: null == evaluations ? _self.evaluations : evaluations // ignore: cast_nullable_to_non_nullable
as AgentEvaluationSummary,
  ));
}
/// Create a copy of DelegationModelListItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get key {

  return $AccountModelKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of DelegationModelListItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCapabilitiesCopyWith<$Res> get capabilities {

  return $ModelCapabilitiesCopyWith<$Res>(_self.capabilities, (value) {
    return _then(_self.copyWith(capabilities: value));
  });
}/// Create a copy of DelegationModelListItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelPricingCopyWith<$Res>? get pricing {
    if (_self.pricing == null) {
    return null;
  }

  return $ModelPricingCopyWith<$Res>(_self.pricing!, (value) {
    return _then(_self.copyWith(pricing: value));
  });
}/// Create a copy of DelegationModelListItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LocalModelPerformanceSummaryCopyWith<$Res> get performance {

  return $LocalModelPerformanceSummaryCopyWith<$Res>(_self.performance, (value) {
    return _then(_self.copyWith(performance: value));
  });
}/// Create a copy of DelegationModelListItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentEvaluationSummaryCopyWith<$Res> get evaluations {

  return $AgentEvaluationSummaryCopyWith<$Res>(_self.evaluations, (value) {
    return _then(_self.copyWith(evaluations: value));
  });
}
}


/// Adds pattern-matching-related methods to [DelegationModelListItem].
extension DelegationModelListItemPatterns on DelegationModelListItem {
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
mixin _$DelegationModelReadTarget {

 ConfigurationRoleReadTarget get sources; AccountModelKey get model;
/// Create a copy of DelegationModelReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DelegationModelReadTargetCopyWith<DelegationModelReadTarget> get copyWith => _$DelegationModelReadTargetCopyWithImpl<DelegationModelReadTarget>(this as DelegationModelReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DelegationModelReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DelegationModelReadTarget&&(identical(other.sources, _this.sources) || other.sources == _this.sources)&&(identical(other.model, _this.model) || other.model == _this.model));
}


@override
int get hashCode {
  final _this = this as DelegationModelReadTarget;
  return Object.hash(runtimeType,_this.sources,_this.model);
}

@override
String toString() {
  final _this = this as DelegationModelReadTarget;
  return 'DelegationModelReadTarget(sources: ${_this.sources}, model: ${_this.model})';
}


}

/// @nodoc
abstract mixin class $DelegationModelReadTargetCopyWith<$Res>  {
  factory $DelegationModelReadTargetCopyWith(DelegationModelReadTarget value, $Res Function(DelegationModelReadTarget) _then) = _$DelegationModelReadTargetCopyWithImpl;
@useResult
$Res call({
 ConfigurationRoleReadTarget sources, AccountModelKey model
});


$ConfigurationRoleReadTargetCopyWith<$Res> get sources;$AccountModelKeyCopyWith<$Res> get model;

}
/// @nodoc
class _$DelegationModelReadTargetCopyWithImpl<$Res>
    implements $DelegationModelReadTargetCopyWith<$Res> {
  _$DelegationModelReadTargetCopyWithImpl(this._self, this._then);

  final DelegationModelReadTarget _self;
  final $Res Function(DelegationModelReadTarget) _then;

/// Create a copy of DelegationModelReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sources = null,Object? model = null,}) {
  return _then(DelegationModelReadTarget(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey,
  ));
}
/// Create a copy of DelegationModelReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res> get sources {

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of DelegationModelReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get model {

  return $AccountModelKeyCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}
}


/// Adds pattern-matching-related methods to [DelegationModelReadTarget].
extension DelegationModelReadTargetPatterns on DelegationModelReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DelegationModelReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DelegationModelReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DelegationModelReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _DelegationModelReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DelegationModelReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _DelegationModelReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationRoleReadTarget sources,  AccountModelKey model)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DelegationModelReadTarget() when $default != null:
return $default(_that.sources,_that.model);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationRoleReadTarget sources,  AccountModelKey model)  $default,) {final _that = this;
switch (_that) {
case _DelegationModelReadTarget():
return $default(_that.sources,_that.model);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationRoleReadTarget sources,  AccountModelKey model)?  $default,) {final _that = this;
switch (_that) {
case _DelegationModelReadTarget() when $default != null:
return $default(_that.sources,_that.model);case _:
  return null;

}
}

}

/// @nodoc


class _DelegationModelReadTarget implements DelegationModelReadTarget {
  const _DelegationModelReadTarget({required this.sources, required this.model});


@override final  ConfigurationRoleReadTarget sources;
@override final  AccountModelKey model;

/// Create a copy of DelegationModelReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DelegationModelReadTargetCopyWith<_DelegationModelReadTarget> get copyWith => __$DelegationModelReadTargetCopyWithImpl<_DelegationModelReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DelegationModelReadTarget&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.model, model) || other.model == model));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sources,model);
}

@override
String toString() {
    return 'DelegationModelReadTarget(sources: $sources, model: $model)';
}


}

/// @nodoc
abstract mixin class _$DelegationModelReadTargetCopyWith<$Res> implements $DelegationModelReadTargetCopyWith<$Res> {
  factory _$DelegationModelReadTargetCopyWith(_DelegationModelReadTarget value, $Res Function(_DelegationModelReadTarget) _then) = __$DelegationModelReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationRoleReadTarget sources, AccountModelKey model
});


@override $ConfigurationRoleReadTargetCopyWith<$Res> get sources;@override $AccountModelKeyCopyWith<$Res> get model;

}
/// @nodoc
class __$DelegationModelReadTargetCopyWithImpl<$Res>
    implements _$DelegationModelReadTargetCopyWith<$Res> {
  __$DelegationModelReadTargetCopyWithImpl(this._self, this._then);

  final _DelegationModelReadTarget _self;
  final $Res Function(_DelegationModelReadTarget) _then;

/// Create a copy of DelegationModelReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sources = null,Object? model = null,}) {
  return _then(_DelegationModelReadTarget(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey,
  ));
}

/// Create a copy of DelegationModelReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res> get sources {

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of DelegationModelReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get model {

  return $AccountModelKeyCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}
}

/// @nodoc
mixin _$DelegationModelDetail {


/// Create a copy of DelegationModelDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DelegationModelDetailCopyWith<DelegationModelDetail> get copyWith => _$DelegationModelDetailCopyWithImpl<DelegationModelDetail>(this as DelegationModelDetail, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DelegationModelDetail;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DelegationModelDetail&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.accountName, _this.accountName) || other.accountName == _this.accountName)&&(identical(other.descriptor, _this.descriptor) || other.descriptor == _this.descriptor)&&(identical(other.available, _this.available) || other.available == _this.available)&&(identical(other.unavailableReason, _this.unavailableReason) || other.unavailableReason == _this.unavailableReason)&&(identical(other.billingKind, _this.billingKind) || other.billingKind == _this.billingKind)&&(identical(other.guide, _this.guide) || other.guide == _this.guide)&&(identical(other.performance, _this.performance) || other.performance == _this.performance)&&(identical(other.evaluations, _this.evaluations) || other.evaluations == _this.evaluations)&&const DeepCollectionEquality().equals(other.recentEvaluations, _this.recentEvaluations));
}


@override
int get hashCode {
  final _this = this as DelegationModelDetail;
  return Object.hash(runtimeType,_this.target,_this.scope,_this.accountName,_this.descriptor,_this.available,_this.unavailableReason,_this.billingKind,_this.guide,_this.performance,_this.evaluations,const DeepCollectionEquality().hash(_this.recentEvaluations));
}



}

/// @nodoc
abstract mixin class $DelegationModelDetailCopyWith<$Res>  {
  factory $DelegationModelDetailCopyWith(DelegationModelDetail value, $Res Function(DelegationModelDetail) _then) = _$DelegationModelDetailCopyWithImpl;
@useResult
$Res call({
 DelegationModelReadTarget target, ProductReadScopeIdentity scope, String accountName, ModelDescriptor descriptor, bool available, String? unavailableReason, BillingKind billingKind, ModelSelectionGuide? guide, LocalModelPerformanceSummary performance, AgentEvaluationSummary evaluations, List<AgentEvaluation> recentEvaluations
});


$DelegationModelReadTargetCopyWith<$Res> get target;$ProductReadScopeIdentityCopyWith<$Res> get scope;$ModelDescriptorCopyWith<$Res> get descriptor;$ModelSelectionGuideCopyWith<$Res>? get guide;$LocalModelPerformanceSummaryCopyWith<$Res> get performance;$AgentEvaluationSummaryCopyWith<$Res> get evaluations;

}
/// @nodoc
class _$DelegationModelDetailCopyWithImpl<$Res>
    implements $DelegationModelDetailCopyWith<$Res> {
  _$DelegationModelDetailCopyWithImpl(this._self, this._then);

  final DelegationModelDetail _self;
  final $Res Function(DelegationModelDetail) _then;

/// Create a copy of DelegationModelDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? target = null,Object? scope = null,Object? accountName = null,Object? descriptor = null,Object? available = null,Object? unavailableReason = freezed,Object? billingKind = null,Object? guide = freezed,Object? performance = null,Object? evaluations = null,Object? recentEvaluations = null,}) {
  return _then(DelegationModelDetail(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as DelegationModelReadTarget,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ProductReadScopeIdentity,accountName: null == accountName ? _self.accountName : accountName // ignore: cast_nullable_to_non_nullable
as String,descriptor: null == descriptor ? _self.descriptor : descriptor // ignore: cast_nullable_to_non_nullable
as ModelDescriptor,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,unavailableReason: freezed == unavailableReason ? _self.unavailableReason : unavailableReason // ignore: cast_nullable_to_non_nullable
as String?,billingKind: null == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind,guide: freezed == guide ? _self.guide : guide // ignore: cast_nullable_to_non_nullable
as ModelSelectionGuide?,performance: null == performance ? _self.performance : performance // ignore: cast_nullable_to_non_nullable
as LocalModelPerformanceSummary,evaluations: null == evaluations ? _self.evaluations : evaluations // ignore: cast_nullable_to_non_nullable
as AgentEvaluationSummary,recentEvaluations: null == recentEvaluations ? _self.recentEvaluations : recentEvaluations // ignore: cast_nullable_to_non_nullable
as List<AgentEvaluation>,
  ));
}
/// Create a copy of DelegationModelDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationModelReadTargetCopyWith<$Res> get target {

  return $DelegationModelReadTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of DelegationModelDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadScopeIdentityCopyWith<$Res> get scope {

  return $ProductReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of DelegationModelDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelDescriptorCopyWith<$Res> get descriptor {

  return $ModelDescriptorCopyWith<$Res>(_self.descriptor, (value) {
    return _then(_self.copyWith(descriptor: value));
  });
}/// Create a copy of DelegationModelDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionGuideCopyWith<$Res>? get guide {
    if (_self.guide == null) {
    return null;
  }

  return $ModelSelectionGuideCopyWith<$Res>(_self.guide!, (value) {
    return _then(_self.copyWith(guide: value));
  });
}/// Create a copy of DelegationModelDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LocalModelPerformanceSummaryCopyWith<$Res> get performance {

  return $LocalModelPerformanceSummaryCopyWith<$Res>(_self.performance, (value) {
    return _then(_self.copyWith(performance: value));
  });
}/// Create a copy of DelegationModelDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentEvaluationSummaryCopyWith<$Res> get evaluations {

  return $AgentEvaluationSummaryCopyWith<$Res>(_self.evaluations, (value) {
    return _then(_self.copyWith(evaluations: value));
  });
}
}


/// Adds pattern-matching-related methods to [DelegationModelDetail].
extension DelegationModelDetailPatterns on DelegationModelDetail {
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
