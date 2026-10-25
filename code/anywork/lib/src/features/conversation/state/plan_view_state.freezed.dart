// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plan_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlanViewState {

 String get threadId; ThreadFacetStamp? get origin; PlanBrief? get plan; PlanDocumentValue? get document;/// The reading panel is open in the conversation reading area.
 bool get open;/// Full-width reading instead of side-by-side. A narrow window forces this
/// at layout time without writing it here.
 bool get fullWidth;/// Current side-by-side panel width; the split component owns the drag.
 double get panelWidth; bool get loading; int get latestIntent; StudioFailure? get error;
/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanViewStateCopyWith<PlanViewState> get copyWith => _$PlanViewStateCopyWithImpl<PlanViewState>(this as PlanViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlanViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanViewState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.plan, _this.plan) || other.plan == _this.plan)&&(identical(other.document, _this.document) || other.document == _this.document)&&(identical(other.open, _this.open) || other.open == _this.open)&&(identical(other.fullWidth, _this.fullWidth) || other.fullWidth == _this.fullWidth)&&(identical(other.panelWidth, _this.panelWidth) || other.panelWidth == _this.panelWidth)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as PlanViewState;
  return Object.hash(runtimeType,_this.threadId,_this.origin,_this.plan,_this.document,_this.open,_this.fullWidth,_this.panelWidth,_this.loading,_this.latestIntent,_this.error);
}



}

/// @nodoc
abstract mixin class $PlanViewStateCopyWith<$Res>  {
  factory $PlanViewStateCopyWith(PlanViewState value, $Res Function(PlanViewState) _then) = _$PlanViewStateCopyWithImpl;
@useResult
$Res call({
 String threadId, ThreadFacetStamp? origin, PlanBrief? plan, PlanDocumentValue? document, bool open, bool fullWidth, double panelWidth, bool loading, int latestIntent, StudioFailure? error
});


$ThreadFacetStampCopyWith<$Res>? get origin;$PlanBriefCopyWith<$Res>? get plan;$PlanDocumentValueCopyWith<$Res>? get document;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$PlanViewStateCopyWithImpl<$Res>
    implements $PlanViewStateCopyWith<$Res> {
  _$PlanViewStateCopyWithImpl(this._self, this._then);

  final PlanViewState _self;
  final $Res Function(PlanViewState) _then;

/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? origin = freezed,Object? plan = freezed,Object? document = freezed,Object? open = null,Object? fullWidth = null,Object? panelWidth = null,Object? loading = null,Object? latestIntent = null,Object? error = freezed,}) {
  return _then(PlanViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,origin: freezed == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,plan: freezed == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as PlanBrief?,document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as PlanDocumentValue?,open: null == open ? _self.open : open // ignore: cast_nullable_to_non_nullable
as bool,fullWidth: null == fullWidth ? _self.fullWidth : fullWidth // ignore: cast_nullable_to_non_nullable
as bool,panelWidth: null == panelWidth ? _self.panelWidth : panelWidth // ignore: cast_nullable_to_non_nullable
as double,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get origin {
    if (_self.origin == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.origin!, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanBriefCopyWith<$Res>? get plan {
    if (_self.plan == null) {
    return null;
  }

  return $PlanBriefCopyWith<$Res>(_self.plan!, (value) {
    return _then(_self.copyWith(plan: value));
  });
}/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanDocumentValueCopyWith<$Res>? get document {
    if (_self.document == null) {
    return null;
  }

  return $PlanDocumentValueCopyWith<$Res>(_self.document!, (value) {
    return _then(_self.copyWith(document: value));
  });
}/// Create a copy of PlanViewState
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
}
}


/// Adds pattern-matching-related methods to [PlanViewState].
extension PlanViewStatePatterns on PlanViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlanViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlanViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlanViewState value)  $default,){
final _that = this;
switch (_that) {
case _PlanViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlanViewState value)?  $default,){
final _that = this;
switch (_that) {
case _PlanViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  ThreadFacetStamp? origin,  PlanBrief? plan,  PlanDocumentValue? document,  bool open,  bool fullWidth,  double panelWidth,  bool loading,  int latestIntent,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlanViewState() when $default != null:
return $default(_that.threadId,_that.origin,_that.plan,_that.document,_that.open,_that.fullWidth,_that.panelWidth,_that.loading,_that.latestIntent,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  ThreadFacetStamp? origin,  PlanBrief? plan,  PlanDocumentValue? document,  bool open,  bool fullWidth,  double panelWidth,  bool loading,  int latestIntent,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _PlanViewState():
return $default(_that.threadId,_that.origin,_that.plan,_that.document,_that.open,_that.fullWidth,_that.panelWidth,_that.loading,_that.latestIntent,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  ThreadFacetStamp? origin,  PlanBrief? plan,  PlanDocumentValue? document,  bool open,  bool fullWidth,  double panelWidth,  bool loading,  int latestIntent,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _PlanViewState() when $default != null:
return $default(_that.threadId,_that.origin,_that.plan,_that.document,_that.open,_that.fullWidth,_that.panelWidth,_that.loading,_that.latestIntent,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _PlanViewState implements PlanViewState {
  const _PlanViewState({required this.threadId, this.origin, this.plan, this.document, this.open = false, this.fullWidth = false, this.panelWidth = planDefaultPanelWidth, this.loading = false, this.latestIntent = 0, this.error});


@override final  String threadId;
@override final  ThreadFacetStamp? origin;
@override final  PlanBrief? plan;
@override final  PlanDocumentValue? document;
/// The reading panel is open in the conversation reading area.
@override@JsonKey() final  bool open;
/// Full-width reading instead of side-by-side. A narrow window forces this
/// at layout time without writing it here.
@override@JsonKey() final  bool fullWidth;
/// Current side-by-side panel width; the split component owns the drag.
@override@JsonKey() final  double panelWidth;
@override@JsonKey() final  bool loading;
@override@JsonKey() final  int latestIntent;
@override final  StudioFailure? error;

/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanViewStateCopyWith<_PlanViewState> get copyWith => __$PlanViewStateCopyWithImpl<_PlanViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanViewState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.plan, plan) || other.plan == plan)&&(identical(other.document, document) || other.document == document)&&(identical(other.open, open) || other.open == open)&&(identical(other.fullWidth, fullWidth) || other.fullWidth == fullWidth)&&(identical(other.panelWidth, panelWidth) || other.panelWidth == panelWidth)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,origin,plan,document,open,fullWidth,panelWidth,loading,latestIntent,error);
}



}

/// @nodoc
abstract mixin class _$PlanViewStateCopyWith<$Res> implements $PlanViewStateCopyWith<$Res> {
  factory _$PlanViewStateCopyWith(_PlanViewState value, $Res Function(_PlanViewState) _then) = __$PlanViewStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, ThreadFacetStamp? origin, PlanBrief? plan, PlanDocumentValue? document, bool open, bool fullWidth, double panelWidth, bool loading, int latestIntent, StudioFailure? error
});


@override $ThreadFacetStampCopyWith<$Res>? get origin;@override $PlanBriefCopyWith<$Res>? get plan;@override $PlanDocumentValueCopyWith<$Res>? get document;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$PlanViewStateCopyWithImpl<$Res>
    implements _$PlanViewStateCopyWith<$Res> {
  __$PlanViewStateCopyWithImpl(this._self, this._then);

  final _PlanViewState _self;
  final $Res Function(_PlanViewState) _then;

/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? origin = freezed,Object? plan = freezed,Object? document = freezed,Object? open = null,Object? fullWidth = null,Object? panelWidth = null,Object? loading = null,Object? latestIntent = null,Object? error = freezed,}) {
  return _then(_PlanViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,origin: freezed == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,plan: freezed == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as PlanBrief?,document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as PlanDocumentValue?,open: null == open ? _self.open : open // ignore: cast_nullable_to_non_nullable
as bool,fullWidth: null == fullWidth ? _self.fullWidth : fullWidth // ignore: cast_nullable_to_non_nullable
as bool,panelWidth: null == panelWidth ? _self.panelWidth : panelWidth // ignore: cast_nullable_to_non_nullable
as double,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get origin {
    if (_self.origin == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.origin!, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanBriefCopyWith<$Res>? get plan {
    if (_self.plan == null) {
    return null;
  }

  return $PlanBriefCopyWith<$Res>(_self.plan!, (value) {
    return _then(_self.copyWith(plan: value));
  });
}/// Create a copy of PlanViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanDocumentValueCopyWith<$Res>? get document {
    if (_self.document == null) {
    return null;
  }

  return $PlanDocumentValueCopyWith<$Res>(_self.document!, (value) {
    return _then(_self.copyWith(document: value));
  });
}/// Create a copy of PlanViewState
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
}
}

// dart format on
