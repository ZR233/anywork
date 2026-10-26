// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_runtime_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadRuntimeSnapshot {


/// Create a copy of ThreadRuntimeSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadRuntimeSnapshotCopyWith<ThreadRuntimeSnapshot> get copyWith => _$ThreadRuntimeSnapshotCopyWithImpl<ThreadRuntimeSnapshot>(this as ThreadRuntimeSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadRuntimeSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadRuntimeSnapshot&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.modelRoute, _this.modelRoute) || other.modelRoute == _this.modelRoute)&&(identical(other.usage, _this.usage) || other.usage == _this.usage)&&(identical(other.liveUsage, _this.liveUsage) || other.liveUsage == _this.liveUsage)&&(identical(other.turnCompletionTokens, _this.turnCompletionTokens) || other.turnCompletionTokens == _this.turnCompletionTokens)&&(identical(other.turnResponseMillis, _this.turnResponseMillis) || other.turnResponseMillis == _this.turnResponseMillis)&&(identical(other.todo, _this.todo) || other.todo == _this.todo)&&const DeepCollectionEquality().equals(other.activeSkills, _this.activeSkills)&&const DeepCollectionEquality().equals(other.activeMcpServers, _this.activeMcpServers)&&const DeepCollectionEquality().equals(other.activeLspServers, _this.activeLspServers)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&(identical(other.mcpHealth, _this.mcpHealth) || other.mcpHealth == _this.mcpHealth)&&(identical(other.workflow, _this.workflow) || other.workflow == _this.workflow)&&(identical(other.plan, _this.plan) || other.plan == _this.plan)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as ThreadRuntimeSnapshot;
  return Object.hash(runtimeType,_this.threadId,_this.modelRoute,_this.usage,_this.liveUsage,_this.turnCompletionTokens,_this.turnResponseMillis,_this.todo,const DeepCollectionEquality().hash(_this.activeSkills),const DeepCollectionEquality().hash(_this.activeMcpServers),const DeepCollectionEquality().hash(_this.activeLspServers),_this.progress,_this.mcpHealth,_this.workflow,_this.plan,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $ThreadRuntimeSnapshotCopyWith<$Res>  {
  factory $ThreadRuntimeSnapshotCopyWith(ThreadRuntimeSnapshot value, $Res Function(ThreadRuntimeSnapshot) _then) = _$ThreadRuntimeSnapshotCopyWithImpl;
@useResult
$Res call({
 String threadId, ThreadModelRoute? modelRoute, ThreadRuntimeUsage usage, ThreadRuntimeLiveUsage? liveUsage, int turnCompletionTokens, int turnResponseMillis, ThreadTodoSnapshot? todo, List<String> activeSkills, List<String> activeMcpServers, List<String> activeLspServers, String? progress, ThreadMcpHealthSnapshot? mcpHealth, ThreadWorkflowSnapshot? workflow, ThreadPlanSnapshot? plan, int updatedAt
});


$ThreadModelRouteCopyWith<$Res>? get modelRoute;$ThreadRuntimeUsageCopyWith<$Res> get usage;$ThreadRuntimeLiveUsageCopyWith<$Res>? get liveUsage;$ThreadTodoSnapshotCopyWith<$Res>? get todo;$ThreadMcpHealthSnapshotCopyWith<$Res>? get mcpHealth;$ThreadWorkflowSnapshotCopyWith<$Res>? get workflow;$ThreadPlanSnapshotCopyWith<$Res>? get plan;

}
/// @nodoc
class _$ThreadRuntimeSnapshotCopyWithImpl<$Res>
    implements $ThreadRuntimeSnapshotCopyWith<$Res> {
  _$ThreadRuntimeSnapshotCopyWithImpl(this._self, this._then);

  final ThreadRuntimeSnapshot _self;
  final $Res Function(ThreadRuntimeSnapshot) _then;

/// Create a copy of ThreadRuntimeSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? modelRoute = freezed,Object? usage = null,Object? liveUsage = freezed,Object? turnCompletionTokens = null,Object? turnResponseMillis = null,Object? todo = freezed,Object? activeSkills = null,Object? activeMcpServers = null,Object? activeLspServers = null,Object? progress = freezed,Object? mcpHealth = freezed,Object? workflow = freezed,Object? plan = freezed,Object? updatedAt = null,}) {
  return _then(ThreadRuntimeSnapshot(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as ThreadModelRoute?,usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as ThreadRuntimeUsage,liveUsage: freezed == liveUsage ? _self.liveUsage : liveUsage // ignore: cast_nullable_to_non_nullable
as ThreadRuntimeLiveUsage?,turnCompletionTokens: null == turnCompletionTokens ? _self.turnCompletionTokens : turnCompletionTokens // ignore: cast_nullable_to_non_nullable
as int,turnResponseMillis: null == turnResponseMillis ? _self.turnResponseMillis : turnResponseMillis // ignore: cast_nullable_to_non_nullable
as int,todo: freezed == todo ? _self.todo : todo // ignore: cast_nullable_to_non_nullable
as ThreadTodoSnapshot?,activeSkills: null == activeSkills ? _self.activeSkills : activeSkills // ignore: cast_nullable_to_non_nullable
as List<String>,activeMcpServers: null == activeMcpServers ? _self.activeMcpServers : activeMcpServers // ignore: cast_nullable_to_non_nullable
as List<String>,activeLspServers: null == activeLspServers ? _self.activeLspServers : activeLspServers // ignore: cast_nullable_to_non_nullable
as List<String>,progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as String?,mcpHealth: freezed == mcpHealth ? _self.mcpHealth : mcpHealth // ignore: cast_nullable_to_non_nullable
as ThreadMcpHealthSnapshot?,workflow: freezed == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as ThreadWorkflowSnapshot?,plan: freezed == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as ThreadPlanSnapshot?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ThreadRuntimeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadModelRouteCopyWith<$Res>? get modelRoute {
    if (_self.modelRoute == null) {
    return null;
  }

  return $ThreadModelRouteCopyWith<$Res>(_self.modelRoute!, (value) {
    return _then(_self.copyWith(modelRoute: value));
  });
}/// Create a copy of ThreadRuntimeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadRuntimeUsageCopyWith<$Res> get usage {

  return $ThreadRuntimeUsageCopyWith<$Res>(_self.usage, (value) {
    return _then(_self.copyWith(usage: value));
  });
}/// Create a copy of ThreadRuntimeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadRuntimeLiveUsageCopyWith<$Res>? get liveUsage {
    if (_self.liveUsage == null) {
    return null;
  }

  return $ThreadRuntimeLiveUsageCopyWith<$Res>(_self.liveUsage!, (value) {
    return _then(_self.copyWith(liveUsage: value));
  });
}/// Create a copy of ThreadRuntimeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadTodoSnapshotCopyWith<$Res>? get todo {
    if (_self.todo == null) {
    return null;
  }

  return $ThreadTodoSnapshotCopyWith<$Res>(_self.todo!, (value) {
    return _then(_self.copyWith(todo: value));
  });
}/// Create a copy of ThreadRuntimeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMcpHealthSnapshotCopyWith<$Res>? get mcpHealth {
    if (_self.mcpHealth == null) {
    return null;
  }

  return $ThreadMcpHealthSnapshotCopyWith<$Res>(_self.mcpHealth!, (value) {
    return _then(_self.copyWith(mcpHealth: value));
  });
}/// Create a copy of ThreadRuntimeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadWorkflowSnapshotCopyWith<$Res>? get workflow {
    if (_self.workflow == null) {
    return null;
  }

  return $ThreadWorkflowSnapshotCopyWith<$Res>(_self.workflow!, (value) {
    return _then(_self.copyWith(workflow: value));
  });
}/// Create a copy of ThreadRuntimeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadPlanSnapshotCopyWith<$Res>? get plan {
    if (_self.plan == null) {
    return null;
  }

  return $ThreadPlanSnapshotCopyWith<$Res>(_self.plan!, (value) {
    return _then(_self.copyWith(plan: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadRuntimeSnapshot].
extension ThreadRuntimeSnapshotPatterns on ThreadRuntimeSnapshot {
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
mixin _$ThreadRuntimeUsage {


/// Create a copy of ThreadRuntimeUsage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadRuntimeUsageCopyWith<ThreadRuntimeUsage> get copyWith => _$ThreadRuntimeUsageCopyWithImpl<ThreadRuntimeUsage>(this as ThreadRuntimeUsage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadRuntimeUsage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadRuntimeUsage&&(identical(other.hasIncompleteUsage, _this.hasIncompleteUsage) || other.hasIncompleteUsage == _this.hasIncompleteUsage)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.maxContextWindow, _this.maxContextWindow) || other.maxContextWindow == _this.maxContextWindow)&&(identical(other.autoCompactLimit, _this.autoCompactLimit) || other.autoCompactLimit == _this.autoCompactLimit)&&(identical(other.latestContextTokens, _this.latestContextTokens) || other.latestContextTokens == _this.latestContextTokens)&&(identical(other.promptTokens, _this.promptTokens) || other.promptTokens == _this.promptTokens)&&(identical(other.completionTokens, _this.completionTokens) || other.completionTokens == _this.completionTokens)&&(identical(other.cachedPromptTokens, _this.cachedPromptTokens) || other.cachedPromptTokens == _this.cachedPromptTokens)&&(identical(other.cacheWriteTokens, _this.cacheWriteTokens) || other.cacheWriteTokens == _this.cacheWriteTokens)&&(identical(other.reasoningTokens, _this.reasoningTokens) || other.reasoningTokens == _this.reasoningTokens)&&(identical(other.inferenceCount, _this.inferenceCount) || other.inferenceCount == _this.inferenceCount)&&(identical(other.totalTokens, _this.totalTokens) || other.totalTokens == _this.totalTokens)&&(identical(other.cacheUsage, _this.cacheUsage) || other.cacheUsage == _this.cacheUsage)&&const DeepCollectionEquality().equals(other.estimatedCosts, _this.estimatedCosts)&&const DeepCollectionEquality().equals(other.estimatedCacheSavings, _this.estimatedCacheSavings)&&(identical(other.hasUnpricedUsage, _this.hasUnpricedUsage) || other.hasUnpricedUsage == _this.hasUnpricedUsage)&&(identical(other.promptGeneration, _this.promptGeneration) || other.promptGeneration == _this.promptGeneration)&&(identical(other.promptCachePolicy, _this.promptCachePolicy) || other.promptCachePolicy == _this.promptCachePolicy)&&(identical(other.prefixChangedReason, _this.prefixChangedReason) || other.prefixChangedReason == _this.prefixChangedReason)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as ThreadRuntimeUsage;
  return Object.hashAll([runtimeType,_this.hasIncompleteUsage,_this.modelId,_this.contextWindow,_this.maxContextWindow,_this.autoCompactLimit,_this.latestContextTokens,_this.promptTokens,_this.completionTokens,_this.cachedPromptTokens,_this.cacheWriteTokens,_this.reasoningTokens,_this.inferenceCount,_this.totalTokens,_this.cacheUsage,const DeepCollectionEquality().hash(_this.estimatedCosts),const DeepCollectionEquality().hash(_this.estimatedCacheSavings),_this.hasUnpricedUsage,_this.promptGeneration,_this.promptCachePolicy,_this.prefixChangedReason,_this.updatedAt]);
}



}

/// @nodoc
abstract mixin class $ThreadRuntimeUsageCopyWith<$Res>  {
  factory $ThreadRuntimeUsageCopyWith(ThreadRuntimeUsage value, $Res Function(ThreadRuntimeUsage) _then) = _$ThreadRuntimeUsageCopyWithImpl;
@useResult
$Res call({
 bool hasIncompleteUsage, String modelId, int? contextWindow, int? maxContextWindow, int? autoCompactLimit, int latestContextTokens, int promptTokens, int completionTokens, int cachedPromptTokens, int cacheWriteTokens, int reasoningTokens, int inferenceCount, int totalTokens, CacheUsageSummary cacheUsage, List<ThreadRuntimeCost> estimatedCosts, List<ThreadRuntimeCost> estimatedCacheSavings, bool hasUnpricedUsage, int? promptGeneration, String? promptCachePolicy, PromptPrefixChangedReason? prefixChangedReason, int updatedAt
});


$CacheUsageSummaryCopyWith<$Res> get cacheUsage;

}
/// @nodoc
class _$ThreadRuntimeUsageCopyWithImpl<$Res>
    implements $ThreadRuntimeUsageCopyWith<$Res> {
  _$ThreadRuntimeUsageCopyWithImpl(this._self, this._then);

  final ThreadRuntimeUsage _self;
  final $Res Function(ThreadRuntimeUsage) _then;

/// Create a copy of ThreadRuntimeUsage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? hasIncompleteUsage = null,Object? modelId = null,Object? contextWindow = freezed,Object? maxContextWindow = freezed,Object? autoCompactLimit = freezed,Object? latestContextTokens = null,Object? promptTokens = null,Object? completionTokens = null,Object? cachedPromptTokens = null,Object? cacheWriteTokens = null,Object? reasoningTokens = null,Object? inferenceCount = null,Object? totalTokens = null,Object? cacheUsage = null,Object? estimatedCosts = null,Object? estimatedCacheSavings = null,Object? hasUnpricedUsage = null,Object? promptGeneration = freezed,Object? promptCachePolicy = freezed,Object? prefixChangedReason = freezed,Object? updatedAt = null,}) {
  return _then(ThreadRuntimeUsage(
hasIncompleteUsage: null == hasIncompleteUsage ? _self.hasIncompleteUsage : hasIncompleteUsage // ignore: cast_nullable_to_non_nullable
as bool,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxContextWindow: freezed == maxContextWindow ? _self.maxContextWindow : maxContextWindow // ignore: cast_nullable_to_non_nullable
as int?,autoCompactLimit: freezed == autoCompactLimit ? _self.autoCompactLimit : autoCompactLimit // ignore: cast_nullable_to_non_nullable
as int?,latestContextTokens: null == latestContextTokens ? _self.latestContextTokens : latestContextTokens // ignore: cast_nullable_to_non_nullable
as int,promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,cachedPromptTokens: null == cachedPromptTokens ? _self.cachedPromptTokens : cachedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,cacheWriteTokens: null == cacheWriteTokens ? _self.cacheWriteTokens : cacheWriteTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningTokens: null == reasoningTokens ? _self.reasoningTokens : reasoningTokens // ignore: cast_nullable_to_non_nullable
as int,inferenceCount: null == inferenceCount ? _self.inferenceCount : inferenceCount // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,cacheUsage: null == cacheUsage ? _self.cacheUsage : cacheUsage // ignore: cast_nullable_to_non_nullable
as CacheUsageSummary,estimatedCosts: null == estimatedCosts ? _self.estimatedCosts : estimatedCosts // ignore: cast_nullable_to_non_nullable
as List<ThreadRuntimeCost>,estimatedCacheSavings: null == estimatedCacheSavings ? _self.estimatedCacheSavings : estimatedCacheSavings // ignore: cast_nullable_to_non_nullable
as List<ThreadRuntimeCost>,hasUnpricedUsage: null == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool,promptGeneration: freezed == promptGeneration ? _self.promptGeneration : promptGeneration // ignore: cast_nullable_to_non_nullable
as int?,promptCachePolicy: freezed == promptCachePolicy ? _self.promptCachePolicy : promptCachePolicy // ignore: cast_nullable_to_non_nullable
as String?,prefixChangedReason: freezed == prefixChangedReason ? _self.prefixChangedReason : prefixChangedReason // ignore: cast_nullable_to_non_nullable
as PromptPrefixChangedReason?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ThreadRuntimeUsage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CacheUsageSummaryCopyWith<$Res> get cacheUsage {

  return $CacheUsageSummaryCopyWith<$Res>(_self.cacheUsage, (value) {
    return _then(_self.copyWith(cacheUsage: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadRuntimeUsage].
extension ThreadRuntimeUsagePatterns on ThreadRuntimeUsage {
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
mixin _$ThreadRuntimeCost {


/// Create a copy of ThreadRuntimeCost
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadRuntimeCostCopyWith<ThreadRuntimeCost> get copyWith => _$ThreadRuntimeCostCopyWithImpl<ThreadRuntimeCost>(this as ThreadRuntimeCost, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadRuntimeCost;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadRuntimeCost&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.amount, _this.amount) || other.amount == _this.amount));
}


@override
int get hashCode {
  final _this = this as ThreadRuntimeCost;
  return Object.hash(runtimeType,_this.currency,_this.amount);
}



}

/// @nodoc
abstract mixin class $ThreadRuntimeCostCopyWith<$Res>  {
  factory $ThreadRuntimeCostCopyWith(ThreadRuntimeCost value, $Res Function(ThreadRuntimeCost) _then) = _$ThreadRuntimeCostCopyWithImpl;
@useResult
$Res call({
 String currency, double amount
});




}
/// @nodoc
class _$ThreadRuntimeCostCopyWithImpl<$Res>
    implements $ThreadRuntimeCostCopyWith<$Res> {
  _$ThreadRuntimeCostCopyWithImpl(this._self, this._then);

  final ThreadRuntimeCost _self;
  final $Res Function(ThreadRuntimeCost) _then;

/// Create a copy of ThreadRuntimeCost
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? currency = null,Object? amount = null,}) {
  return _then(ThreadRuntimeCost(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadRuntimeCost].
extension ThreadRuntimeCostPatterns on ThreadRuntimeCost {
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
mixin _$ThreadRuntimeLiveUsage {


/// Create a copy of ThreadRuntimeLiveUsage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadRuntimeLiveUsageCopyWith<ThreadRuntimeLiveUsage> get copyWith => _$ThreadRuntimeLiveUsageCopyWithImpl<ThreadRuntimeLiveUsage>(this as ThreadRuntimeLiveUsage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadRuntimeLiveUsage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadRuntimeLiveUsage&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.attemptId, _this.attemptId) || other.attemptId == _this.attemptId)&&(identical(other.completionTokens, _this.completionTokens) || other.completionTokens == _this.completionTokens)&&(identical(other.responseMillis, _this.responseMillis) || other.responseMillis == _this.responseMillis)&&(identical(other.latestContextTokens, _this.latestContextTokens) || other.latestContextTokens == _this.latestContextTokens)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.observationSequence, _this.observationSequence) || other.observationSequence == _this.observationSequence));
}


@override
int get hashCode {
  final _this = this as ThreadRuntimeLiveUsage;
  return Object.hash(runtimeType,_this.turnId,_this.attemptId,_this.completionTokens,_this.responseMillis,_this.latestContextTokens,_this.state,_this.observationSequence);
}



}

/// @nodoc
abstract mixin class $ThreadRuntimeLiveUsageCopyWith<$Res>  {
  factory $ThreadRuntimeLiveUsageCopyWith(ThreadRuntimeLiveUsage value, $Res Function(ThreadRuntimeLiveUsage) _then) = _$ThreadRuntimeLiveUsageCopyWithImpl;
@useResult
$Res call({
 String turnId, String attemptId, int? completionTokens, int? responseMillis, int? latestContextTokens, TurnObservationState state, int observationSequence
});




}
/// @nodoc
class _$ThreadRuntimeLiveUsageCopyWithImpl<$Res>
    implements $ThreadRuntimeLiveUsageCopyWith<$Res> {
  _$ThreadRuntimeLiveUsageCopyWithImpl(this._self, this._then);

  final ThreadRuntimeLiveUsage _self;
  final $Res Function(ThreadRuntimeLiveUsage) _then;

/// Create a copy of ThreadRuntimeLiveUsage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? turnId = null,Object? attemptId = null,Object? completionTokens = freezed,Object? responseMillis = freezed,Object? latestContextTokens = freezed,Object? state = null,Object? observationSequence = null,}) {
  return _then(ThreadRuntimeLiveUsage(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,completionTokens: freezed == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int?,responseMillis: freezed == responseMillis ? _self.responseMillis : responseMillis // ignore: cast_nullable_to_non_nullable
as int?,latestContextTokens: freezed == latestContextTokens ? _self.latestContextTokens : latestContextTokens // ignore: cast_nullable_to_non_nullable
as int?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnObservationState,observationSequence: null == observationSequence ? _self.observationSequence : observationSequence // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadRuntimeLiveUsage].
extension ThreadRuntimeLiveUsagePatterns on ThreadRuntimeLiveUsage {
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
mixin _$ThreadTodoSnapshot {


/// Create a copy of ThreadTodoSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadTodoSnapshotCopyWith<ThreadTodoSnapshot> get copyWith => _$ThreadTodoSnapshotCopyWithImpl<ThreadTodoSnapshot>(this as ThreadTodoSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadTodoSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadTodoSnapshot&&(identical(other.callId, _this.callId) || other.callId == _this.callId)&&(identical(other.agentId, _this.agentId) || other.agentId == _this.agentId)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.parentPath, _this.parentPath) || other.parentPath == _this.parentPath)&&(identical(other.explanation, _this.explanation) || other.explanation == _this.explanation)&&const DeepCollectionEquality().equals(other.items, _this.items));
}


@override
int get hashCode {
  final _this = this as ThreadTodoSnapshot;
  return Object.hash(runtimeType,_this.callId,_this.agentId,_this.path,_this.parentPath,_this.explanation,const DeepCollectionEquality().hash(_this.items));
}



}

/// @nodoc
abstract mixin class $ThreadTodoSnapshotCopyWith<$Res>  {
  factory $ThreadTodoSnapshotCopyWith(ThreadTodoSnapshot value, $Res Function(ThreadTodoSnapshot) _then) = _$ThreadTodoSnapshotCopyWithImpl;
@useResult
$Res call({
 String callId, String? agentId, String? path, String? parentPath, String? explanation, List<ThreadTodoItem> items
});




}
/// @nodoc
class _$ThreadTodoSnapshotCopyWithImpl<$Res>
    implements $ThreadTodoSnapshotCopyWith<$Res> {
  _$ThreadTodoSnapshotCopyWithImpl(this._self, this._then);

  final ThreadTodoSnapshot _self;
  final $Res Function(ThreadTodoSnapshot) _then;

/// Create a copy of ThreadTodoSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? callId = null,Object? agentId = freezed,Object? path = freezed,Object? parentPath = freezed,Object? explanation = freezed,Object? items = null,}) {
  return _then(ThreadTodoSnapshot(
callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String,agentId: freezed == agentId ? _self.agentId : agentId // ignore: cast_nullable_to_non_nullable
as String?,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String?,parentPath: freezed == parentPath ? _self.parentPath : parentPath // ignore: cast_nullable_to_non_nullable
as String?,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String?,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ThreadTodoItem>,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadTodoSnapshot].
extension ThreadTodoSnapshotPatterns on ThreadTodoSnapshot {
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
mixin _$ThreadTodoItem {


/// Create a copy of ThreadTodoItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadTodoItemCopyWith<ThreadTodoItem> get copyWith => _$ThreadTodoItemCopyWithImpl<ThreadTodoItem>(this as ThreadTodoItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadTodoItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadTodoItem&&(identical(other.step, _this.step) || other.step == _this.step)&&(identical(other.status, _this.status) || other.status == _this.status));
}


@override
int get hashCode {
  final _this = this as ThreadTodoItem;
  return Object.hash(runtimeType,_this.step,_this.status);
}



}

/// @nodoc
abstract mixin class $ThreadTodoItemCopyWith<$Res>  {
  factory $ThreadTodoItemCopyWith(ThreadTodoItem value, $Res Function(ThreadTodoItem) _then) = _$ThreadTodoItemCopyWithImpl;
@useResult
$Res call({
 String step, TodoItemStatus status
});




}
/// @nodoc
class _$ThreadTodoItemCopyWithImpl<$Res>
    implements $ThreadTodoItemCopyWith<$Res> {
  _$ThreadTodoItemCopyWithImpl(this._self, this._then);

  final ThreadTodoItem _self;
  final $Res Function(ThreadTodoItem) _then;

/// Create a copy of ThreadTodoItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? step = null,Object? status = null,}) {
  return _then(ThreadTodoItem(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TodoItemStatus,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadTodoItem].
extension ThreadTodoItemPatterns on ThreadTodoItem {
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
mixin _$ThreadMcpHealthSnapshot {


/// Create a copy of ThreadMcpHealthSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMcpHealthSnapshotCopyWith<ThreadMcpHealthSnapshot> get copyWith => _$ThreadMcpHealthSnapshotCopyWithImpl<ThreadMcpHealthSnapshot>(this as ThreadMcpHealthSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadMcpHealthSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMcpHealthSnapshot&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&const DeepCollectionEquality().equals(other.servers, _this.servers));
}


@override
int get hashCode {
  final _this = this as ThreadMcpHealthSnapshot;
  return Object.hash(runtimeType,_this.generation,const DeepCollectionEquality().hash(_this.servers));
}



}

/// @nodoc
abstract mixin class $ThreadMcpHealthSnapshotCopyWith<$Res>  {
  factory $ThreadMcpHealthSnapshotCopyWith(ThreadMcpHealthSnapshot value, $Res Function(ThreadMcpHealthSnapshot) _then) = _$ThreadMcpHealthSnapshotCopyWithImpl;
@useResult
$Res call({
 int generation, List<ThreadMcpAvailability> servers
});




}
/// @nodoc
class _$ThreadMcpHealthSnapshotCopyWithImpl<$Res>
    implements $ThreadMcpHealthSnapshotCopyWith<$Res> {
  _$ThreadMcpHealthSnapshotCopyWithImpl(this._self, this._then);

  final ThreadMcpHealthSnapshot _self;
  final $Res Function(ThreadMcpHealthSnapshot) _then;

/// Create a copy of ThreadMcpHealthSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,Object? servers = null,}) {
  return _then(ThreadMcpHealthSnapshot(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,servers: null == servers ? _self.servers : servers // ignore: cast_nullable_to_non_nullable
as List<ThreadMcpAvailability>,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadMcpHealthSnapshot].
extension ThreadMcpHealthSnapshotPatterns on ThreadMcpHealthSnapshot {
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
mixin _$ThreadMcpAvailability {


/// Create a copy of ThreadMcpAvailability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMcpAvailabilityCopyWith<ThreadMcpAvailability> get copyWith => _$ThreadMcpAvailabilityCopyWithImpl<ThreadMcpAvailability>(this as ThreadMcpAvailability, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadMcpAvailability;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMcpAvailability&&(identical(other.server, _this.server) || other.server == _this.server)&&(identical(other.availability, _this.availability) || other.availability == _this.availability)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.lastCheckedAt, _this.lastCheckedAt) || other.lastCheckedAt == _this.lastCheckedAt)&&(identical(other.toolCount, _this.toolCount) || other.toolCount == _this.toolCount));
}


@override
int get hashCode {
  final _this = this as ThreadMcpAvailability;
  return Object.hash(runtimeType,_this.server,_this.availability,_this.message,_this.lastCheckedAt,_this.toolCount);
}



}

/// @nodoc
abstract mixin class $ThreadMcpAvailabilityCopyWith<$Res>  {
  factory $ThreadMcpAvailabilityCopyWith(ThreadMcpAvailability value, $Res Function(ThreadMcpAvailability) _then) = _$ThreadMcpAvailabilityCopyWithImpl;
@useResult
$Res call({
 ThreadMcpServer server, String availability, String? message, int? lastCheckedAt, int? toolCount
});


$ThreadMcpServerCopyWith<$Res> get server;

}
/// @nodoc
class _$ThreadMcpAvailabilityCopyWithImpl<$Res>
    implements $ThreadMcpAvailabilityCopyWith<$Res> {
  _$ThreadMcpAvailabilityCopyWithImpl(this._self, this._then);

  final ThreadMcpAvailability _self;
  final $Res Function(ThreadMcpAvailability) _then;

/// Create a copy of ThreadMcpAvailability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? server = null,Object? availability = null,Object? message = freezed,Object? lastCheckedAt = freezed,Object? toolCount = freezed,}) {
  return _then(ThreadMcpAvailability(
server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as ThreadMcpServer,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as String,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,toolCount: freezed == toolCount ? _self.toolCount : toolCount // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of ThreadMcpAvailability
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMcpServerCopyWith<$Res> get server {

  return $ThreadMcpServerCopyWith<$Res>(_self.server, (value) {
    return _then(_self.copyWith(server: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadMcpAvailability].
extension ThreadMcpAvailabilityPatterns on ThreadMcpAvailability {
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
mixin _$ThreadMcpServer {


/// Create a copy of ThreadMcpServer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMcpServerCopyWith<ThreadMcpServer> get copyWith => _$ThreadMcpServerCopyWithImpl<ThreadMcpServer>(this as ThreadMcpServer, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadMcpServer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMcpServer&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.transport, _this.transport) || other.transport == _this.transport)&&(identical(other.endpoint, _this.endpoint) || other.endpoint == _this.endpoint)&&(identical(other.builtIn, _this.builtIn) || other.builtIn == _this.builtIn));
}


@override
int get hashCode {
  final _this = this as ThreadMcpServer;
  return Object.hash(runtimeType,_this.id,_this.source,_this.transport,_this.endpoint,_this.builtIn);
}



}

/// @nodoc
abstract mixin class $ThreadMcpServerCopyWith<$Res>  {
  factory $ThreadMcpServerCopyWith(ThreadMcpServer value, $Res Function(ThreadMcpServer) _then) = _$ThreadMcpServerCopyWithImpl;
@useResult
$Res call({
 String id, String source, String transport, String endpoint, bool builtIn
});




}
/// @nodoc
class _$ThreadMcpServerCopyWithImpl<$Res>
    implements $ThreadMcpServerCopyWith<$Res> {
  _$ThreadMcpServerCopyWithImpl(this._self, this._then);

  final ThreadMcpServer _self;
  final $Res Function(ThreadMcpServer) _then;

/// Create a copy of ThreadMcpServer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? source = null,Object? transport = null,Object? endpoint = null,Object? builtIn = null,}) {
  return _then(ThreadMcpServer(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as String,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,builtIn: null == builtIn ? _self.builtIn : builtIn // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadMcpServer].
extension ThreadMcpServerPatterns on ThreadMcpServer {
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
mixin _$ThreadWorkflowSnapshot {


/// Create a copy of ThreadWorkflowSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadWorkflowSnapshotCopyWith<ThreadWorkflowSnapshot> get copyWith => _$ThreadWorkflowSnapshotCopyWithImpl<ThreadWorkflowSnapshot>(this as ThreadWorkflowSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadWorkflowSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadWorkflowSnapshot&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.currentRun, _this.currentRun) || other.currentRun == _this.currentRun));
}


@override
int get hashCode {
  final _this = this as ThreadWorkflowSnapshot;
  return Object.hash(runtimeType,_this.revision,_this.currentRun);
}



}

/// @nodoc
abstract mixin class $ThreadWorkflowSnapshotCopyWith<$Res>  {
  factory $ThreadWorkflowSnapshotCopyWith(ThreadWorkflowSnapshot value, $Res Function(ThreadWorkflowSnapshot) _then) = _$ThreadWorkflowSnapshotCopyWithImpl;
@useResult
$Res call({
 int revision, ThreadWorkflowRun? currentRun
});


$ThreadWorkflowRunCopyWith<$Res>? get currentRun;

}
/// @nodoc
class _$ThreadWorkflowSnapshotCopyWithImpl<$Res>
    implements $ThreadWorkflowSnapshotCopyWith<$Res> {
  _$ThreadWorkflowSnapshotCopyWithImpl(this._self, this._then);

  final ThreadWorkflowSnapshot _self;
  final $Res Function(ThreadWorkflowSnapshot) _then;

/// Create a copy of ThreadWorkflowSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? currentRun = freezed,}) {
  return _then(ThreadWorkflowSnapshot(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,currentRun: freezed == currentRun ? _self.currentRun : currentRun // ignore: cast_nullable_to_non_nullable
as ThreadWorkflowRun?,
  ));
}
/// Create a copy of ThreadWorkflowSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadWorkflowRunCopyWith<$Res>? get currentRun {
    if (_self.currentRun == null) {
    return null;
  }

  return $ThreadWorkflowRunCopyWith<$Res>(_self.currentRun!, (value) {
    return _then(_self.copyWith(currentRun: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadWorkflowSnapshot].
extension ThreadWorkflowSnapshotPatterns on ThreadWorkflowSnapshot {
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
mixin _$ThreadWorkflowRun {


/// Create a copy of ThreadWorkflowRun
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadWorkflowRunCopyWith<ThreadWorkflowRun> get copyWith => _$ThreadWorkflowRunCopyWithImpl<ThreadWorkflowRun>(this as ThreadWorkflowRun, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadWorkflowRun;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadWorkflowRun&&(identical(other.lineageId, _this.lineageId) || other.lineageId == _this.lineageId)&&(identical(other.runId, _this.runId) || other.runId == _this.runId)&&(identical(other.modeId, _this.modeId) || other.modeId == _this.modeId)&&(identical(other.graphRevision, _this.graphRevision) || other.graphRevision == _this.graphRevision)&&(identical(other.graphHash, _this.graphHash) || other.graphHash == _this.graphHash)&&(identical(other.lifecycle, _this.lifecycle) || other.lifecycle == _this.lifecycle)&&(identical(other.currentStateId, _this.currentStateId) || other.currentStateId == _this.currentStateId)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.currentStateTitle, _this.currentStateTitle) || other.currentStateTitle == _this.currentStateTitle)&&(identical(other.modeDisplayName, _this.modeDisplayName) || other.modeDisplayName == _this.modeDisplayName)&&(identical(other.modeDeleted, _this.modeDeleted) || other.modeDeleted == _this.modeDeleted));
}


@override
int get hashCode {
  final _this = this as ThreadWorkflowRun;
  return Object.hash(runtimeType,_this.lineageId,_this.runId,_this.modeId,_this.graphRevision,_this.graphHash,_this.lifecycle,_this.currentStateId,_this.startedAt,_this.updatedAt,_this.currentStateTitle,_this.modeDisplayName,_this.modeDeleted);
}



}

/// @nodoc
abstract mixin class $ThreadWorkflowRunCopyWith<$Res>  {
  factory $ThreadWorkflowRunCopyWith(ThreadWorkflowRun value, $Res Function(ThreadWorkflowRun) _then) = _$ThreadWorkflowRunCopyWithImpl;
@useResult
$Res call({
 String lineageId, String runId, String modeId, int graphRevision, String graphHash, WorkflowLifecycle lifecycle, String currentStateId, int startedAt, int updatedAt, String currentStateTitle, String modeDisplayName, bool modeDeleted
});




}
/// @nodoc
class _$ThreadWorkflowRunCopyWithImpl<$Res>
    implements $ThreadWorkflowRunCopyWith<$Res> {
  _$ThreadWorkflowRunCopyWithImpl(this._self, this._then);

  final ThreadWorkflowRun _self;
  final $Res Function(ThreadWorkflowRun) _then;

/// Create a copy of ThreadWorkflowRun
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lineageId = null,Object? runId = null,Object? modeId = null,Object? graphRevision = null,Object? graphHash = null,Object? lifecycle = null,Object? currentStateId = null,Object? startedAt = null,Object? updatedAt = null,Object? currentStateTitle = null,Object? modeDisplayName = null,Object? modeDeleted = null,}) {
  return _then(ThreadWorkflowRun(
lineageId: null == lineageId ? _self.lineageId : lineageId // ignore: cast_nullable_to_non_nullable
as String,runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,modeId: null == modeId ? _self.modeId : modeId // ignore: cast_nullable_to_non_nullable
as String,graphRevision: null == graphRevision ? _self.graphRevision : graphRevision // ignore: cast_nullable_to_non_nullable
as int,graphHash: null == graphHash ? _self.graphHash : graphHash // ignore: cast_nullable_to_non_nullable
as String,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as WorkflowLifecycle,currentStateId: null == currentStateId ? _self.currentStateId : currentStateId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,currentStateTitle: null == currentStateTitle ? _self.currentStateTitle : currentStateTitle // ignore: cast_nullable_to_non_nullable
as String,modeDisplayName: null == modeDisplayName ? _self.modeDisplayName : modeDisplayName // ignore: cast_nullable_to_non_nullable
as String,modeDeleted: null == modeDeleted ? _self.modeDeleted : modeDeleted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadWorkflowRun].
extension ThreadWorkflowRunPatterns on ThreadWorkflowRun {
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
mixin _$ThreadPlanSnapshot {


/// Create a copy of ThreadPlanSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadPlanSnapshotCopyWith<ThreadPlanSnapshot> get copyWith => _$ThreadPlanSnapshotCopyWithImpl<ThreadPlanSnapshot>(this as ThreadPlanSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadPlanSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadPlanSnapshot&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.document, _this.document) || other.document == _this.document)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as ThreadPlanSnapshot;
  return Object.hash(runtimeType,_this.revision,_this.state,_this.document,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $ThreadPlanSnapshotCopyWith<$Res>  {
  factory $ThreadPlanSnapshotCopyWith(ThreadPlanSnapshot value, $Res Function(ThreadPlanSnapshot) _then) = _$ThreadPlanSnapshotCopyWithImpl;
@useResult
$Res call({
 int revision, PlanPhase state, ThreadPlanDocument? document, int updatedAt
});


$ThreadPlanDocumentCopyWith<$Res>? get document;

}
/// @nodoc
class _$ThreadPlanSnapshotCopyWithImpl<$Res>
    implements $ThreadPlanSnapshotCopyWith<$Res> {
  _$ThreadPlanSnapshotCopyWithImpl(this._self, this._then);

  final ThreadPlanSnapshot _self;
  final $Res Function(ThreadPlanSnapshot) _then;

/// Create a copy of ThreadPlanSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? state = null,Object? document = freezed,Object? updatedAt = null,}) {
  return _then(ThreadPlanSnapshot(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PlanPhase,document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ThreadPlanDocument?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ThreadPlanSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadPlanDocumentCopyWith<$Res>? get document {
    if (_self.document == null) {
    return null;
  }

  return $ThreadPlanDocumentCopyWith<$Res>(_self.document!, (value) {
    return _then(_self.copyWith(document: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadPlanSnapshot].
extension ThreadPlanSnapshotPatterns on ThreadPlanSnapshot {
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
mixin _$ThreadPlanDocument {


/// Create a copy of ThreadPlanDocument
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadPlanDocumentCopyWith<ThreadPlanDocument> get copyWith => _$ThreadPlanDocumentCopyWithImpl<ThreadPlanDocument>(this as ThreadPlanDocument, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadPlanDocument;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadPlanDocument&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.markdown, _this.markdown) || other.markdown == _this.markdown)&&(identical(other.contentHash, _this.contentHash) || other.contentHash == _this.contentHash));
}


@override
int get hashCode {
  final _this = this as ThreadPlanDocument;
  return Object.hash(runtimeType,_this.version,_this.markdown,_this.contentHash);
}



}

/// @nodoc
abstract mixin class $ThreadPlanDocumentCopyWith<$Res>  {
  factory $ThreadPlanDocumentCopyWith(ThreadPlanDocument value, $Res Function(ThreadPlanDocument) _then) = _$ThreadPlanDocumentCopyWithImpl;
@useResult
$Res call({
 int version, String markdown, String contentHash
});




}
/// @nodoc
class _$ThreadPlanDocumentCopyWithImpl<$Res>
    implements $ThreadPlanDocumentCopyWith<$Res> {
  _$ThreadPlanDocumentCopyWithImpl(this._self, this._then);

  final ThreadPlanDocument _self;
  final $Res Function(ThreadPlanDocument) _then;

/// Create a copy of ThreadPlanDocument
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? markdown = null,Object? contentHash = null,}) {
  return _then(ThreadPlanDocument(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,markdown: null == markdown ? _self.markdown : markdown // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadPlanDocument].
extension ThreadPlanDocumentPatterns on ThreadPlanDocument {
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
