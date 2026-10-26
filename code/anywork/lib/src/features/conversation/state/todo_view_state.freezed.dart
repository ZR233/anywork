// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'todo_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TodoViewState {

 String get threadId; ThreadFacetStamp? get origin; TodoBrief? get todo; TodoReadHeader? get header; List<TodoReadItem> get items; Map<int, TextReadProgress> get texts; int? get nextOffset; bool get expanded; bool get loading; int get generation; StudioFailure? get error;
/// Create a copy of TodoViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TodoViewStateCopyWith<TodoViewState> get copyWith => _$TodoViewStateCopyWithImpl<TodoViewState>(this as TodoViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TodoViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TodoViewState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.todo, _this.todo) || other.todo == _this.todo)&&(identical(other.header, _this.header) || other.header == _this.header)&&const DeepCollectionEquality().equals(other.items, _this.items)&&const DeepCollectionEquality().equals(other.texts, _this.texts)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset)&&(identical(other.expanded, _this.expanded) || other.expanded == _this.expanded)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as TodoViewState;
  return Object.hash(runtimeType,_this.threadId,_this.origin,_this.todo,_this.header,const DeepCollectionEquality().hash(_this.items),const DeepCollectionEquality().hash(_this.texts),_this.nextOffset,_this.expanded,_this.loading,_this.generation,_this.error);
}



}

/// @nodoc
abstract mixin class $TodoViewStateCopyWith<$Res>  {
  factory $TodoViewStateCopyWith(TodoViewState value, $Res Function(TodoViewState) _then) = _$TodoViewStateCopyWithImpl;
@useResult
$Res call({
 String threadId, ThreadFacetStamp? origin, TodoBrief? todo, TodoReadHeader? header, List<TodoReadItem> items, Map<int, TextReadProgress> texts, int? nextOffset, bool expanded, bool loading, int generation, StudioFailure? error
});


$ThreadFacetStampCopyWith<$Res>? get origin;$TodoBriefCopyWith<$Res>? get todo;$TodoReadHeaderCopyWith<$Res>? get header;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$TodoViewStateCopyWithImpl<$Res>
    implements $TodoViewStateCopyWith<$Res> {
  _$TodoViewStateCopyWithImpl(this._self, this._then);

  final TodoViewState _self;
  final $Res Function(TodoViewState) _then;

/// Create a copy of TodoViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? origin = freezed,Object? todo = freezed,Object? header = freezed,Object? items = null,Object? texts = null,Object? nextOffset = freezed,Object? expanded = null,Object? loading = null,Object? generation = null,Object? error = freezed,}) {
  return _then(TodoViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,origin: freezed == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,todo: freezed == todo ? _self.todo : todo // ignore: cast_nullable_to_non_nullable
as TodoBrief?,header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as TodoReadHeader?,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<TodoReadItem>,texts: null == texts ? _self.texts : texts // ignore: cast_nullable_to_non_nullable
as Map<int, TextReadProgress>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,expanded: null == expanded ? _self.expanded : expanded // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of TodoViewState
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
}/// Create a copy of TodoViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoBriefCopyWith<$Res>? get todo {
    if (_self.todo == null) {
    return null;
  }

  return $TodoBriefCopyWith<$Res>(_self.todo!, (value) {
    return _then(_self.copyWith(todo: value));
  });
}/// Create a copy of TodoViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoReadHeaderCopyWith<$Res>? get header {
    if (_self.header == null) {
    return null;
  }

  return $TodoReadHeaderCopyWith<$Res>(_self.header!, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of TodoViewState
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


/// Adds pattern-matching-related methods to [TodoViewState].
extension TodoViewStatePatterns on TodoViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TodoViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TodoViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TodoViewState value)  $default,){
final _that = this;
switch (_that) {
case _TodoViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TodoViewState value)?  $default,){
final _that = this;
switch (_that) {
case _TodoViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  ThreadFacetStamp? origin,  TodoBrief? todo,  TodoReadHeader? header,  List<TodoReadItem> items,  Map<int, TextReadProgress> texts,  int? nextOffset,  bool expanded,  bool loading,  int generation,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TodoViewState() when $default != null:
return $default(_that.threadId,_that.origin,_that.todo,_that.header,_that.items,_that.texts,_that.nextOffset,_that.expanded,_that.loading,_that.generation,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  ThreadFacetStamp? origin,  TodoBrief? todo,  TodoReadHeader? header,  List<TodoReadItem> items,  Map<int, TextReadProgress> texts,  int? nextOffset,  bool expanded,  bool loading,  int generation,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _TodoViewState():
return $default(_that.threadId,_that.origin,_that.todo,_that.header,_that.items,_that.texts,_that.nextOffset,_that.expanded,_that.loading,_that.generation,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  ThreadFacetStamp? origin,  TodoBrief? todo,  TodoReadHeader? header,  List<TodoReadItem> items,  Map<int, TextReadProgress> texts,  int? nextOffset,  bool expanded,  bool loading,  int generation,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _TodoViewState() when $default != null:
return $default(_that.threadId,_that.origin,_that.todo,_that.header,_that.items,_that.texts,_that.nextOffset,_that.expanded,_that.loading,_that.generation,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _TodoViewState extends TodoViewState {
  const _TodoViewState({required this.threadId, this.origin, this.todo, this.header,  List<TodoReadItem> items = const [],  Map<int, TextReadProgress> texts = const {}, this.nextOffset, this.expanded = false, this.loading = false, this.generation = 0, this.error}): _items = items,_texts = texts,super._();


@override final  String threadId;
@override final  ThreadFacetStamp? origin;
@override final  TodoBrief? todo;
@override final  TodoReadHeader? header;
 final  List<TodoReadItem> _items;
@override@JsonKey() List<TodoReadItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

 final  Map<int, TextReadProgress> _texts;
@override@JsonKey() Map<int, TextReadProgress> get texts {
  if (_texts is EqualUnmodifiableMapView) return _texts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_texts);
}

@override final  int? nextOffset;
@override@JsonKey() final  bool expanded;
@override@JsonKey() final  bool loading;
@override@JsonKey() final  int generation;
@override final  StudioFailure? error;

/// Create a copy of TodoViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TodoViewStateCopyWith<_TodoViewState> get copyWith => __$TodoViewStateCopyWithImpl<_TodoViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TodoViewState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.todo, todo) || other.todo == todo)&&(identical(other.header, header) || other.header == header)&&const DeepCollectionEquality().equals(other.items, _items)&&const DeepCollectionEquality().equals(other.texts, _texts)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset)&&(identical(other.expanded, expanded) || other.expanded == expanded)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,origin,todo,header,const DeepCollectionEquality().hash(_items),const DeepCollectionEquality().hash(_texts),nextOffset,expanded,loading,generation,error);
}



}

/// @nodoc
abstract mixin class _$TodoViewStateCopyWith<$Res> implements $TodoViewStateCopyWith<$Res> {
  factory _$TodoViewStateCopyWith(_TodoViewState value, $Res Function(_TodoViewState) _then) = __$TodoViewStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, ThreadFacetStamp? origin, TodoBrief? todo, TodoReadHeader? header, List<TodoReadItem> items, Map<int, TextReadProgress> texts, int? nextOffset, bool expanded, bool loading, int generation, StudioFailure? error
});


@override $ThreadFacetStampCopyWith<$Res>? get origin;@override $TodoBriefCopyWith<$Res>? get todo;@override $TodoReadHeaderCopyWith<$Res>? get header;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$TodoViewStateCopyWithImpl<$Res>
    implements _$TodoViewStateCopyWith<$Res> {
  __$TodoViewStateCopyWithImpl(this._self, this._then);

  final _TodoViewState _self;
  final $Res Function(_TodoViewState) _then;

/// Create a copy of TodoViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? origin = freezed,Object? todo = freezed,Object? header = freezed,Object? items = null,Object? texts = null,Object? nextOffset = freezed,Object? expanded = null,Object? loading = null,Object? generation = null,Object? error = freezed,}) {
  return _then(_TodoViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,origin: freezed == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,todo: freezed == todo ? _self.todo : todo // ignore: cast_nullable_to_non_nullable
as TodoBrief?,header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as TodoReadHeader?,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<TodoReadItem>,texts: null == texts ? _self._texts : texts // ignore: cast_nullable_to_non_nullable
as Map<int, TextReadProgress>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,expanded: null == expanded ? _self.expanded : expanded // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of TodoViewState
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
}/// Create a copy of TodoViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoBriefCopyWith<$Res>? get todo {
    if (_self.todo == null) {
    return null;
  }

  return $TodoBriefCopyWith<$Res>(_self.todo!, (value) {
    return _then(_self.copyWith(todo: value));
  });
}/// Create a copy of TodoViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TodoReadHeaderCopyWith<$Res>? get header {
    if (_self.header == null) {
    return null;
  }

  return $TodoReadHeaderCopyWith<$Res>(_self.header!, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of TodoViewState
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
