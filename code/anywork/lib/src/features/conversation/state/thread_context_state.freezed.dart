// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_context_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadContextViewState {

 String get threadId; ThreadContextState? get source; ThreadStatus? get status; ContextReadHeader? get header; List<CostReadItem> get costs; List<CostReadItem> get cacheSavings; Map<int, TextReadProgress> get texts; int? get nextCostOffset; int? get nextSavingOffset; bool get detailsVisible; bool get loading; int get generation; StudioFailure? get error; OperationState? get compaction;
/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextViewStateCopyWith<ThreadContextViewState> get copyWith => _$ThreadContextViewStateCopyWithImpl<ThreadContextViewState>(this as ThreadContextViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadContextViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextViewState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.header, _this.header) || other.header == _this.header)&&const DeepCollectionEquality().equals(other.costs, _this.costs)&&const DeepCollectionEquality().equals(other.cacheSavings, _this.cacheSavings)&&const DeepCollectionEquality().equals(other.texts, _this.texts)&&(identical(other.nextCostOffset, _this.nextCostOffset) || other.nextCostOffset == _this.nextCostOffset)&&(identical(other.nextSavingOffset, _this.nextSavingOffset) || other.nextSavingOffset == _this.nextSavingOffset)&&(identical(other.detailsVisible, _this.detailsVisible) || other.detailsVisible == _this.detailsVisible)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.compaction, _this.compaction) || other.compaction == _this.compaction));
}


@override
int get hashCode {
  final _this = this as ThreadContextViewState;
  return Object.hash(runtimeType,_this.threadId,_this.source,_this.status,_this.header,const DeepCollectionEquality().hash(_this.costs),const DeepCollectionEquality().hash(_this.cacheSavings),const DeepCollectionEquality().hash(_this.texts),_this.nextCostOffset,_this.nextSavingOffset,_this.detailsVisible,_this.loading,_this.generation,_this.error,_this.compaction);
}



}

/// @nodoc
abstract mixin class $ThreadContextViewStateCopyWith<$Res>  {
  factory $ThreadContextViewStateCopyWith(ThreadContextViewState value, $Res Function(ThreadContextViewState) _then) = _$ThreadContextViewStateCopyWithImpl;
@useResult
$Res call({
 String threadId, ThreadContextState? source, ThreadStatus? status, ContextReadHeader? header, List<CostReadItem> costs, List<CostReadItem> cacheSavings, Map<int, TextReadProgress> texts, int? nextCostOffset, int? nextSavingOffset, bool detailsVisible, bool loading, int generation, StudioFailure? error, OperationState? compaction
});


$ThreadContextStateCopyWith<$Res>? get source;$ContextReadHeaderCopyWith<$Res>? get header;$StudioFailureCopyWith<$Res>? get error;$OperationStateCopyWith<$Res>? get compaction;

}
/// @nodoc
class _$ThreadContextViewStateCopyWithImpl<$Res>
    implements $ThreadContextViewStateCopyWith<$Res> {
  _$ThreadContextViewStateCopyWithImpl(this._self, this._then);

  final ThreadContextViewState _self;
  final $Res Function(ThreadContextViewState) _then;

/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? source = freezed,Object? status = freezed,Object? header = freezed,Object? costs = null,Object? cacheSavings = null,Object? texts = null,Object? nextCostOffset = freezed,Object? nextSavingOffset = freezed,Object? detailsVisible = null,Object? loading = null,Object? generation = null,Object? error = freezed,Object? compaction = freezed,}) {
  return _then(ThreadContextViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ThreadContextState?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus?,header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ContextReadHeader?,costs: null == costs ? _self.costs : costs // ignore: cast_nullable_to_non_nullable
as List<CostReadItem>,cacheSavings: null == cacheSavings ? _self.cacheSavings : cacheSavings // ignore: cast_nullable_to_non_nullable
as List<CostReadItem>,texts: null == texts ? _self.texts : texts // ignore: cast_nullable_to_non_nullable
as Map<int, TextReadProgress>,nextCostOffset: freezed == nextCostOffset ? _self.nextCostOffset : nextCostOffset // ignore: cast_nullable_to_non_nullable
as int?,nextSavingOffset: freezed == nextSavingOffset ? _self.nextSavingOffset : nextSavingOffset // ignore: cast_nullable_to_non_nullable
as int?,detailsVisible: null == detailsVisible ? _self.detailsVisible : detailsVisible // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,compaction: freezed == compaction ? _self.compaction : compaction // ignore: cast_nullable_to_non_nullable
as OperationState?,
  ));
}
/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContextStateCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $ThreadContextStateCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContextReadHeaderCopyWith<$Res>? get header {
    if (_self.header == null) {
    return null;
  }

  return $ContextReadHeaderCopyWith<$Res>(_self.header!, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get compaction {
    if (_self.compaction == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.compaction!, (value) {
    return _then(_self.copyWith(compaction: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadContextViewState].
extension ThreadContextViewStatePatterns on ThreadContextViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadContextViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadContextViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadContextViewState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadContextViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadContextViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadContextViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  ThreadContextState? source,  ThreadStatus? status,  ContextReadHeader? header,  List<CostReadItem> costs,  List<CostReadItem> cacheSavings,  Map<int, TextReadProgress> texts,  int? nextCostOffset,  int? nextSavingOffset,  bool detailsVisible,  bool loading,  int generation,  StudioFailure? error,  OperationState? compaction)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadContextViewState() when $default != null:
return $default(_that.threadId,_that.source,_that.status,_that.header,_that.costs,_that.cacheSavings,_that.texts,_that.nextCostOffset,_that.nextSavingOffset,_that.detailsVisible,_that.loading,_that.generation,_that.error,_that.compaction);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  ThreadContextState? source,  ThreadStatus? status,  ContextReadHeader? header,  List<CostReadItem> costs,  List<CostReadItem> cacheSavings,  Map<int, TextReadProgress> texts,  int? nextCostOffset,  int? nextSavingOffset,  bool detailsVisible,  bool loading,  int generation,  StudioFailure? error,  OperationState? compaction)  $default,) {final _that = this;
switch (_that) {
case _ThreadContextViewState():
return $default(_that.threadId,_that.source,_that.status,_that.header,_that.costs,_that.cacheSavings,_that.texts,_that.nextCostOffset,_that.nextSavingOffset,_that.detailsVisible,_that.loading,_that.generation,_that.error,_that.compaction);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  ThreadContextState? source,  ThreadStatus? status,  ContextReadHeader? header,  List<CostReadItem> costs,  List<CostReadItem> cacheSavings,  Map<int, TextReadProgress> texts,  int? nextCostOffset,  int? nextSavingOffset,  bool detailsVisible,  bool loading,  int generation,  StudioFailure? error,  OperationState? compaction)?  $default,) {final _that = this;
switch (_that) {
case _ThreadContextViewState() when $default != null:
return $default(_that.threadId,_that.source,_that.status,_that.header,_that.costs,_that.cacheSavings,_that.texts,_that.nextCostOffset,_that.nextSavingOffset,_that.detailsVisible,_that.loading,_that.generation,_that.error,_that.compaction);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadContextViewState extends ThreadContextViewState {
  const _ThreadContextViewState({required this.threadId, this.source, this.status, this.header,  List<CostReadItem> costs = const [],  List<CostReadItem> cacheSavings = const [],  Map<int, TextReadProgress> texts = const {}, this.nextCostOffset, this.nextSavingOffset, this.detailsVisible = false, this.loading = false, this.generation = 0, this.error, this.compaction}): _costs = costs,_cacheSavings = cacheSavings,_texts = texts,super._();


@override final  String threadId;
@override final  ThreadContextState? source;
@override final  ThreadStatus? status;
@override final  ContextReadHeader? header;
 final  List<CostReadItem> _costs;
@override@JsonKey() List<CostReadItem> get costs {
  if (_costs is EqualUnmodifiableListView) return _costs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_costs);
}

 final  List<CostReadItem> _cacheSavings;
@override@JsonKey() List<CostReadItem> get cacheSavings {
  if (_cacheSavings is EqualUnmodifiableListView) return _cacheSavings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_cacheSavings);
}

 final  Map<int, TextReadProgress> _texts;
@override@JsonKey() Map<int, TextReadProgress> get texts {
  if (_texts is EqualUnmodifiableMapView) return _texts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_texts);
}

@override final  int? nextCostOffset;
@override final  int? nextSavingOffset;
@override@JsonKey() final  bool detailsVisible;
@override@JsonKey() final  bool loading;
@override@JsonKey() final  int generation;
@override final  StudioFailure? error;
@override final  OperationState? compaction;

/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadContextViewStateCopyWith<_ThreadContextViewState> get copyWith => __$ThreadContextViewStateCopyWithImpl<_ThreadContextViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadContextViewState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.source, source) || other.source == source)&&(identical(other.status, status) || other.status == status)&&(identical(other.header, header) || other.header == header)&&const DeepCollectionEquality().equals(other.costs, _costs)&&const DeepCollectionEquality().equals(other.cacheSavings, _cacheSavings)&&const DeepCollectionEquality().equals(other.texts, _texts)&&(identical(other.nextCostOffset, nextCostOffset) || other.nextCostOffset == nextCostOffset)&&(identical(other.nextSavingOffset, nextSavingOffset) || other.nextSavingOffset == nextSavingOffset)&&(identical(other.detailsVisible, detailsVisible) || other.detailsVisible == detailsVisible)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.error, error) || other.error == error)&&(identical(other.compaction, compaction) || other.compaction == compaction));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,source,status,header,const DeepCollectionEquality().hash(_costs),const DeepCollectionEquality().hash(_cacheSavings),const DeepCollectionEquality().hash(_texts),nextCostOffset,nextSavingOffset,detailsVisible,loading,generation,error,compaction);
}



}

/// @nodoc
abstract mixin class _$ThreadContextViewStateCopyWith<$Res> implements $ThreadContextViewStateCopyWith<$Res> {
  factory _$ThreadContextViewStateCopyWith(_ThreadContextViewState value, $Res Function(_ThreadContextViewState) _then) = __$ThreadContextViewStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, ThreadContextState? source, ThreadStatus? status, ContextReadHeader? header, List<CostReadItem> costs, List<CostReadItem> cacheSavings, Map<int, TextReadProgress> texts, int? nextCostOffset, int? nextSavingOffset, bool detailsVisible, bool loading, int generation, StudioFailure? error, OperationState? compaction
});


@override $ThreadContextStateCopyWith<$Res>? get source;@override $ContextReadHeaderCopyWith<$Res>? get header;@override $StudioFailureCopyWith<$Res>? get error;@override $OperationStateCopyWith<$Res>? get compaction;

}
/// @nodoc
class __$ThreadContextViewStateCopyWithImpl<$Res>
    implements _$ThreadContextViewStateCopyWith<$Res> {
  __$ThreadContextViewStateCopyWithImpl(this._self, this._then);

  final _ThreadContextViewState _self;
  final $Res Function(_ThreadContextViewState) _then;

/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? source = freezed,Object? status = freezed,Object? header = freezed,Object? costs = null,Object? cacheSavings = null,Object? texts = null,Object? nextCostOffset = freezed,Object? nextSavingOffset = freezed,Object? detailsVisible = null,Object? loading = null,Object? generation = null,Object? error = freezed,Object? compaction = freezed,}) {
  return _then(_ThreadContextViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ThreadContextState?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus?,header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ContextReadHeader?,costs: null == costs ? _self._costs : costs // ignore: cast_nullable_to_non_nullable
as List<CostReadItem>,cacheSavings: null == cacheSavings ? _self._cacheSavings : cacheSavings // ignore: cast_nullable_to_non_nullable
as List<CostReadItem>,texts: null == texts ? _self._texts : texts // ignore: cast_nullable_to_non_nullable
as Map<int, TextReadProgress>,nextCostOffset: freezed == nextCostOffset ? _self.nextCostOffset : nextCostOffset // ignore: cast_nullable_to_non_nullable
as int?,nextSavingOffset: freezed == nextSavingOffset ? _self.nextSavingOffset : nextSavingOffset // ignore: cast_nullable_to_non_nullable
as int?,detailsVisible: null == detailsVisible ? _self.detailsVisible : detailsVisible // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,compaction: freezed == compaction ? _self.compaction : compaction // ignore: cast_nullable_to_non_nullable
as OperationState?,
  ));
}

/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContextStateCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $ThreadContextStateCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContextReadHeaderCopyWith<$Res>? get header {
    if (_self.header == null) {
    return null;
  }

  return $ContextReadHeaderCopyWith<$Res>(_self.header!, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of ThreadContextViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get compaction {
    if (_self.compaction == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.compaction!, (value) {
    return _then(_self.copyWith(compaction: value));
  });
}
}

// dart format on
