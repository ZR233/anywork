// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'selection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WorkspaceSelection {

 String? get projectId; String? get threadId; bool get needsOpen;
/// Create a copy of WorkspaceSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceSelectionCopyWith<WorkspaceSelection> get copyWith => _$WorkspaceSelectionCopyWithImpl<WorkspaceSelection>(this as WorkspaceSelection, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceSelection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceSelection&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.needsOpen, _this.needsOpen) || other.needsOpen == _this.needsOpen));
}


@override
int get hashCode {
  final _this = this as WorkspaceSelection;
  return Object.hash(runtimeType,_this.projectId,_this.threadId,_this.needsOpen);
}

@override
String toString() {
  final _this = this as WorkspaceSelection;
  return 'WorkspaceSelection(projectId: ${_this.projectId}, threadId: ${_this.threadId}, needsOpen: ${_this.needsOpen})';
}


}

/// @nodoc
abstract mixin class $WorkspaceSelectionCopyWith<$Res>  {
  factory $WorkspaceSelectionCopyWith(WorkspaceSelection value, $Res Function(WorkspaceSelection) _then) = _$WorkspaceSelectionCopyWithImpl;
@useResult
$Res call({
 String? projectId, String? threadId, bool needsOpen
});




}
/// @nodoc
class _$WorkspaceSelectionCopyWithImpl<$Res>
    implements $WorkspaceSelectionCopyWith<$Res> {
  _$WorkspaceSelectionCopyWithImpl(this._self, this._then);

  final WorkspaceSelection _self;
  final $Res Function(WorkspaceSelection) _then;

/// Create a copy of WorkspaceSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = freezed,Object? threadId = freezed,Object? needsOpen = null,}) {
  return _then(WorkspaceSelection(
projectId: freezed == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String?,threadId: freezed == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String?,needsOpen: null == needsOpen ? _self.needsOpen : needsOpen // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkspaceSelection].
extension WorkspaceSelectionPatterns on WorkspaceSelection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceSelection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceSelection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceSelection value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceSelection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceSelection value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceSelection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? projectId,  String? threadId,  bool needsOpen)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceSelection() when $default != null:
return $default(_that.projectId,_that.threadId,_that.needsOpen);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? projectId,  String? threadId,  bool needsOpen)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceSelection():
return $default(_that.projectId,_that.threadId,_that.needsOpen);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? projectId,  String? threadId,  bool needsOpen)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceSelection() when $default != null:
return $default(_that.projectId,_that.threadId,_that.needsOpen);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceSelection implements WorkspaceSelection {
  const _WorkspaceSelection({required this.projectId, required this.threadId, required this.needsOpen}): assert(threadId == null || projectId != null),assert(!needsOpen || threadId != null);


@override final  String? projectId;
@override final  String? threadId;
@override final  bool needsOpen;

/// Create a copy of WorkspaceSelection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceSelectionCopyWith<_WorkspaceSelection> get copyWith => __$WorkspaceSelectionCopyWithImpl<_WorkspaceSelection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceSelection&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.needsOpen, needsOpen) || other.needsOpen == needsOpen));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId,threadId,needsOpen);
}

@override
String toString() {
    return 'WorkspaceSelection(projectId: $projectId, threadId: $threadId, needsOpen: $needsOpen)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceSelectionCopyWith<$Res> implements $WorkspaceSelectionCopyWith<$Res> {
  factory _$WorkspaceSelectionCopyWith(_WorkspaceSelection value, $Res Function(_WorkspaceSelection) _then) = __$WorkspaceSelectionCopyWithImpl;
@override @useResult
$Res call({
 String? projectId, String? threadId, bool needsOpen
});




}
/// @nodoc
class __$WorkspaceSelectionCopyWithImpl<$Res>
    implements _$WorkspaceSelectionCopyWith<$Res> {
  __$WorkspaceSelectionCopyWithImpl(this._self, this._then);

  final _WorkspaceSelection _self;
  final $Res Function(_WorkspaceSelection) _then;

/// Create a copy of WorkspaceSelection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = freezed,Object? threadId = freezed,Object? needsOpen = null,}) {
  return _then(_WorkspaceSelection(
projectId: freezed == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String?,threadId: freezed == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String?,needsOpen: null == needsOpen ? _self.needsOpen : needsOpen // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$WorkspaceState {

 WorkspaceSelection get selection; int get selectionGeneration; bool get sealed;
/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<WorkspaceState> get copyWith => _$WorkspaceStateCopyWithImpl<WorkspaceState>(this as WorkspaceState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceState&&(identical(other.selection, _this.selection) || other.selection == _this.selection)&&(identical(other.selectionGeneration, _this.selectionGeneration) || other.selectionGeneration == _this.selectionGeneration)&&(identical(other.sealed, _this.sealed) || other.sealed == _this.sealed));
}


@override
int get hashCode {
  final _this = this as WorkspaceState;
  return Object.hash(runtimeType,_this.selection,_this.selectionGeneration,_this.sealed);
}

@override
String toString() {
  final _this = this as WorkspaceState;
  return 'WorkspaceState(selection: ${_this.selection}, selectionGeneration: ${_this.selectionGeneration}, sealed: ${_this.sealed})';
}


}

/// @nodoc
abstract mixin class $WorkspaceStateCopyWith<$Res>  {
  factory $WorkspaceStateCopyWith(WorkspaceState value, $Res Function(WorkspaceState) _then) = _$WorkspaceStateCopyWithImpl;
@useResult
$Res call({
 WorkspaceSelection selection, int selectionGeneration, bool sealed
});


$WorkspaceSelectionCopyWith<$Res> get selection;

}
/// @nodoc
class _$WorkspaceStateCopyWithImpl<$Res>
    implements $WorkspaceStateCopyWith<$Res> {
  _$WorkspaceStateCopyWithImpl(this._self, this._then);

  final WorkspaceState _self;
  final $Res Function(WorkspaceState) _then;

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? selection = null,Object? selectionGeneration = null,Object? sealed = null,}) {
  return _then(WorkspaceState(
selection: null == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as WorkspaceSelection,selectionGeneration: null == selectionGeneration ? _self.selectionGeneration : selectionGeneration // ignore: cast_nullable_to_non_nullable
as int,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceSelectionCopyWith<$Res> get selection {

  return $WorkspaceSelectionCopyWith<$Res>(_self.selection, (value) {
    return _then(_self.copyWith(selection: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceState].
extension WorkspaceStatePatterns on WorkspaceState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceState value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceState value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorkspaceSelection selection,  int selectionGeneration,  bool sealed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
return $default(_that.selection,_that.selectionGeneration,_that.sealed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorkspaceSelection selection,  int selectionGeneration,  bool sealed)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceState():
return $default(_that.selection,_that.selectionGeneration,_that.sealed);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorkspaceSelection selection,  int selectionGeneration,  bool sealed)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
return $default(_that.selection,_that.selectionGeneration,_that.sealed);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceState implements WorkspaceState {
  const _WorkspaceState({required this.selection, required this.selectionGeneration, required this.sealed});


@override final  WorkspaceSelection selection;
@override final  int selectionGeneration;
@override final  bool sealed;

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceStateCopyWith<_WorkspaceState> get copyWith => __$WorkspaceStateCopyWithImpl<_WorkspaceState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceState&&(identical(other.selection, selection) || other.selection == selection)&&(identical(other.selectionGeneration, selectionGeneration) || other.selectionGeneration == selectionGeneration)&&(identical(other.sealed, sealed) || other.sealed == sealed));
}


@override
int get hashCode {
    return Object.hash(runtimeType,selection,selectionGeneration,sealed);
}

@override
String toString() {
    return 'WorkspaceState(selection: $selection, selectionGeneration: $selectionGeneration, sealed: $sealed)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceStateCopyWith<$Res> implements $WorkspaceStateCopyWith<$Res> {
  factory _$WorkspaceStateCopyWith(_WorkspaceState value, $Res Function(_WorkspaceState) _then) = __$WorkspaceStateCopyWithImpl;
@override @useResult
$Res call({
 WorkspaceSelection selection, int selectionGeneration, bool sealed
});


@override $WorkspaceSelectionCopyWith<$Res> get selection;

}
/// @nodoc
class __$WorkspaceStateCopyWithImpl<$Res>
    implements _$WorkspaceStateCopyWith<$Res> {
  __$WorkspaceStateCopyWithImpl(this._self, this._then);

  final _WorkspaceState _self;
  final $Res Function(_WorkspaceState) _then;

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? selection = null,Object? selectionGeneration = null,Object? sealed = null,}) {
  return _then(_WorkspaceState(
selection: null == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as WorkspaceSelection,selectionGeneration: null == selectionGeneration ? _self.selectionGeneration : selectionGeneration // ignore: cast_nullable_to_non_nullable
as int,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceSelectionCopyWith<$Res> get selection {

  return $WorkspaceSelectionCopyWith<$Res>(_self.selection, (value) {
    return _then(_self.copyWith(selection: value));
  });
}
}

/// @nodoc
mixin _$WorkspaceIntentStamp {

 int get generation;
/// Create a copy of WorkspaceIntentStamp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceIntentStampCopyWith<WorkspaceIntentStamp> get copyWith => _$WorkspaceIntentStampCopyWithImpl<WorkspaceIntentStamp>(this as WorkspaceIntentStamp, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceIntentStamp;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceIntentStamp&&(identical(other.generation, _this.generation) || other.generation == _this.generation));
}


@override
int get hashCode {
  final _this = this as WorkspaceIntentStamp;
  return Object.hash(runtimeType,_this.generation);
}

@override
String toString() {
  final _this = this as WorkspaceIntentStamp;
  return 'WorkspaceIntentStamp(generation: ${_this.generation})';
}


}

/// @nodoc
abstract mixin class $WorkspaceIntentStampCopyWith<$Res>  {
  factory $WorkspaceIntentStampCopyWith(WorkspaceIntentStamp value, $Res Function(WorkspaceIntentStamp) _then) = _$WorkspaceIntentStampCopyWithImpl;
@useResult
$Res call({
 int generation
});




}
/// @nodoc
class _$WorkspaceIntentStampCopyWithImpl<$Res>
    implements $WorkspaceIntentStampCopyWith<$Res> {
  _$WorkspaceIntentStampCopyWithImpl(this._self, this._then);

  final WorkspaceIntentStamp _self;
  final $Res Function(WorkspaceIntentStamp) _then;

/// Create a copy of WorkspaceIntentStamp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,}) {
  return _then(WorkspaceIntentStamp(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkspaceIntentStamp].
extension WorkspaceIntentStampPatterns on WorkspaceIntentStamp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceIntentStamp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceIntentStamp() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceIntentStamp value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceIntentStamp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceIntentStamp value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceIntentStamp() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int generation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceIntentStamp() when $default != null:
return $default(_that.generation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int generation)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceIntentStamp():
return $default(_that.generation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int generation)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceIntentStamp() when $default != null:
return $default(_that.generation);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceIntentStamp implements WorkspaceIntentStamp {
  const _WorkspaceIntentStamp({required this.generation});


@override final  int generation;

/// Create a copy of WorkspaceIntentStamp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceIntentStampCopyWith<_WorkspaceIntentStamp> get copyWith => __$WorkspaceIntentStampCopyWithImpl<_WorkspaceIntentStamp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceIntentStamp&&(identical(other.generation, generation) || other.generation == generation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,generation);
}

@override
String toString() {
    return 'WorkspaceIntentStamp(generation: $generation)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceIntentStampCopyWith<$Res> implements $WorkspaceIntentStampCopyWith<$Res> {
  factory _$WorkspaceIntentStampCopyWith(_WorkspaceIntentStamp value, $Res Function(_WorkspaceIntentStamp) _then) = __$WorkspaceIntentStampCopyWithImpl;
@override @useResult
$Res call({
 int generation
});




}
/// @nodoc
class __$WorkspaceIntentStampCopyWithImpl<$Res>
    implements _$WorkspaceIntentStampCopyWith<$Res> {
  __$WorkspaceIntentStampCopyWithImpl(this._self, this._then);

  final _WorkspaceIntentStamp _self;
  final $Res Function(_WorkspaceIntentStamp) _then;

/// Create a copy of WorkspaceIntentStamp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,}) {
  return _then(_WorkspaceIntentStamp(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$WorkspaceSelectionResult {

 WorkspaceIntentStamp get intent; WorkspaceSelection get selection; SelectionDisposition get disposition;
/// Create a copy of WorkspaceSelectionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceSelectionResultCopyWith<WorkspaceSelectionResult> get copyWith => _$WorkspaceSelectionResultCopyWithImpl<WorkspaceSelectionResult>(this as WorkspaceSelectionResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceSelectionResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceSelectionResult&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.selection, _this.selection) || other.selection == _this.selection)&&(identical(other.disposition, _this.disposition) || other.disposition == _this.disposition));
}


@override
int get hashCode {
  final _this = this as WorkspaceSelectionResult;
  return Object.hash(runtimeType,_this.intent,_this.selection,_this.disposition);
}

@override
String toString() {
  final _this = this as WorkspaceSelectionResult;
  return 'WorkspaceSelectionResult(intent: ${_this.intent}, selection: ${_this.selection}, disposition: ${_this.disposition})';
}


}

/// @nodoc
abstract mixin class $WorkspaceSelectionResultCopyWith<$Res>  {
  factory $WorkspaceSelectionResultCopyWith(WorkspaceSelectionResult value, $Res Function(WorkspaceSelectionResult) _then) = _$WorkspaceSelectionResultCopyWithImpl;
@useResult
$Res call({
 WorkspaceIntentStamp intent, WorkspaceSelection selection, SelectionDisposition disposition
});


$WorkspaceIntentStampCopyWith<$Res> get intent;$WorkspaceSelectionCopyWith<$Res> get selection;

}
/// @nodoc
class _$WorkspaceSelectionResultCopyWithImpl<$Res>
    implements $WorkspaceSelectionResultCopyWith<$Res> {
  _$WorkspaceSelectionResultCopyWithImpl(this._self, this._then);

  final WorkspaceSelectionResult _self;
  final $Res Function(WorkspaceSelectionResult) _then;

/// Create a copy of WorkspaceSelectionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? selection = null,Object? disposition = null,}) {
  return _then(WorkspaceSelectionResult(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as WorkspaceIntentStamp,selection: null == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as WorkspaceSelection,disposition: null == disposition ? _self.disposition : disposition // ignore: cast_nullable_to_non_nullable
as SelectionDisposition,
  ));
}
/// Create a copy of WorkspaceSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceIntentStampCopyWith<$Res> get intent {

  return $WorkspaceIntentStampCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of WorkspaceSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceSelectionCopyWith<$Res> get selection {

  return $WorkspaceSelectionCopyWith<$Res>(_self.selection, (value) {
    return _then(_self.copyWith(selection: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceSelectionResult].
extension WorkspaceSelectionResultPatterns on WorkspaceSelectionResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceSelectionResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceSelectionResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceSelectionResult value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceSelectionResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceSelectionResult value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceSelectionResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorkspaceIntentStamp intent,  WorkspaceSelection selection,  SelectionDisposition disposition)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceSelectionResult() when $default != null:
return $default(_that.intent,_that.selection,_that.disposition);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorkspaceIntentStamp intent,  WorkspaceSelection selection,  SelectionDisposition disposition)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceSelectionResult():
return $default(_that.intent,_that.selection,_that.disposition);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorkspaceIntentStamp intent,  WorkspaceSelection selection,  SelectionDisposition disposition)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceSelectionResult() when $default != null:
return $default(_that.intent,_that.selection,_that.disposition);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceSelectionResult implements WorkspaceSelectionResult {
  const _WorkspaceSelectionResult({required this.intent, required this.selection, required this.disposition});


@override final  WorkspaceIntentStamp intent;
@override final  WorkspaceSelection selection;
@override final  SelectionDisposition disposition;

/// Create a copy of WorkspaceSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceSelectionResultCopyWith<_WorkspaceSelectionResult> get copyWith => __$WorkspaceSelectionResultCopyWithImpl<_WorkspaceSelectionResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceSelectionResult&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.selection, selection) || other.selection == selection)&&(identical(other.disposition, disposition) || other.disposition == disposition));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,selection,disposition);
}

@override
String toString() {
    return 'WorkspaceSelectionResult(intent: $intent, selection: $selection, disposition: $disposition)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceSelectionResultCopyWith<$Res> implements $WorkspaceSelectionResultCopyWith<$Res> {
  factory _$WorkspaceSelectionResultCopyWith(_WorkspaceSelectionResult value, $Res Function(_WorkspaceSelectionResult) _then) = __$WorkspaceSelectionResultCopyWithImpl;
@override @useResult
$Res call({
 WorkspaceIntentStamp intent, WorkspaceSelection selection, SelectionDisposition disposition
});


@override $WorkspaceIntentStampCopyWith<$Res> get intent;@override $WorkspaceSelectionCopyWith<$Res> get selection;

}
/// @nodoc
class __$WorkspaceSelectionResultCopyWithImpl<$Res>
    implements _$WorkspaceSelectionResultCopyWith<$Res> {
  __$WorkspaceSelectionResultCopyWithImpl(this._self, this._then);

  final _WorkspaceSelectionResult _self;
  final $Res Function(_WorkspaceSelectionResult) _then;

/// Create a copy of WorkspaceSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? selection = null,Object? disposition = null,}) {
  return _then(_WorkspaceSelectionResult(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as WorkspaceIntentStamp,selection: null == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as WorkspaceSelection,disposition: null == disposition ? _self.disposition : disposition // ignore: cast_nullable_to_non_nullable
as SelectionDisposition,
  ));
}

/// Create a copy of WorkspaceSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceIntentStampCopyWith<$Res> get intent {

  return $WorkspaceIntentStampCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of WorkspaceSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceSelectionCopyWith<$Res> get selection {

  return $WorkspaceSelectionCopyWith<$Res>(_self.selection, (value) {
    return _then(_self.copyWith(selection: value));
  });
}
}

/// @nodoc
mixin _$ArchiveThreadResult {


/// Create a copy of ArchiveThreadResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArchiveThreadResultCopyWith<ArchiveThreadResult> get copyWith => _$ArchiveThreadResultCopyWithImpl<ArchiveThreadResult>(this as ArchiveThreadResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ArchiveThreadResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArchiveThreadResult&&(identical(other.archivedRootId, _this.archivedRootId) || other.archivedRootId == _this.archivedRootId)&&const DeepCollectionEquality().equals(other.removedThreadIds, _this.removedThreadIds)&&(identical(other.nextRoot, _this.nextRoot) || other.nextRoot == _this.nextRoot));
}


@override
int get hashCode {
  final _this = this as ArchiveThreadResult;
  return Object.hash(runtimeType,_this.archivedRootId,const DeepCollectionEquality().hash(_this.removedThreadIds),_this.nextRoot);
}

@override
String toString() {
  final _this = this as ArchiveThreadResult;
  return 'ArchiveThreadResult(archivedRootId: ${_this.archivedRootId}, removedThreadIds: ${_this.removedThreadIds}, nextRoot: ${_this.nextRoot})';
}


}

/// @nodoc
abstract mixin class $ArchiveThreadResultCopyWith<$Res>  {
  factory $ArchiveThreadResultCopyWith(ArchiveThreadResult value, $Res Function(ArchiveThreadResult) _then) = _$ArchiveThreadResultCopyWithImpl;
@useResult
$Res call({
 String archivedRootId, List<String> removedThreadIds, WorkspaceThreadRecord? nextRoot
});


$WorkspaceThreadRecordCopyWith<$Res>? get nextRoot;

}
/// @nodoc
class _$ArchiveThreadResultCopyWithImpl<$Res>
    implements $ArchiveThreadResultCopyWith<$Res> {
  _$ArchiveThreadResultCopyWithImpl(this._self, this._then);

  final ArchiveThreadResult _self;
  final $Res Function(ArchiveThreadResult) _then;

/// Create a copy of ArchiveThreadResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? archivedRootId = null,Object? removedThreadIds = null,Object? nextRoot = freezed,}) {
  return _then(ArchiveThreadResult(
archivedRootId: null == archivedRootId ? _self.archivedRootId : archivedRootId // ignore: cast_nullable_to_non_nullable
as String,removedThreadIds: null == removedThreadIds ? _self.removedThreadIds : removedThreadIds // ignore: cast_nullable_to_non_nullable
as List<String>,nextRoot: freezed == nextRoot ? _self.nextRoot : nextRoot // ignore: cast_nullable_to_non_nullable
as WorkspaceThreadRecord?,
  ));
}
/// Create a copy of ArchiveThreadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordCopyWith<$Res>? get nextRoot {
    if (_self.nextRoot == null) {
    return null;
  }

  return $WorkspaceThreadRecordCopyWith<$Res>(_self.nextRoot!, (value) {
    return _then(_self.copyWith(nextRoot: value));
  });
}
}


/// Adds pattern-matching-related methods to [ArchiveThreadResult].
extension ArchiveThreadResultPatterns on ArchiveThreadResult {
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
mixin _$WorkspaceOpenStep {

 OperationId get operationId;
/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceOpenStepCopyWith<WorkspaceOpenStep> get copyWith => _$WorkspaceOpenStepCopyWithImpl<WorkspaceOpenStep>(this as WorkspaceOpenStep, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceOpenStep;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceOpenStep&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId));
}


@override
int get hashCode {
  final _this = this as WorkspaceOpenStep;
  return Object.hash(runtimeType,_this.operationId);
}



}

/// @nodoc
abstract mixin class $WorkspaceOpenStepCopyWith<$Res>  {
  factory $WorkspaceOpenStepCopyWith(WorkspaceOpenStep value, $Res Function(WorkspaceOpenStep) _then) = _$WorkspaceOpenStepCopyWithImpl;
@useResult
$Res call({
 OperationId operationId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$WorkspaceOpenStepCopyWithImpl<$Res>
    implements $WorkspaceOpenStepCopyWith<$Res> {
  _$WorkspaceOpenStepCopyWithImpl(this._self, this._then);

  final WorkspaceOpenStep _self;
  final $Res Function(WorkspaceOpenStep) _then;

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,}) {
  return _then(_self.copyWith(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,
  ));
}
/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceOpenStep].
extension WorkspaceOpenStepPatterns on WorkspaceOpenStep {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( OpenedWorkspaceOpenStep value)?  opened,TResult Function( RenamedWorkspaceOpenStep value)?  renamed,TResult Function( ActivatedWorkspaceOpenStep value)?  activated,TResult Function( NotStartedWorkspaceOpenStep value)?  notStarted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case OpenedWorkspaceOpenStep() when opened != null:
return opened(_that);case RenamedWorkspaceOpenStep() when renamed != null:
return renamed(_that);case ActivatedWorkspaceOpenStep() when activated != null:
return activated(_that);case NotStartedWorkspaceOpenStep() when notStarted != null:
return notStarted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( OpenedWorkspaceOpenStep value)  opened,required TResult Function( RenamedWorkspaceOpenStep value)  renamed,required TResult Function( ActivatedWorkspaceOpenStep value)  activated,required TResult Function( NotStartedWorkspaceOpenStep value)  notStarted,}){
final _that = this;
switch (_that) {
case OpenedWorkspaceOpenStep():
return opened(_that);case RenamedWorkspaceOpenStep():
return renamed(_that);case ActivatedWorkspaceOpenStep():
return activated(_that);case NotStartedWorkspaceOpenStep():
return notStarted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( OpenedWorkspaceOpenStep value)?  opened,TResult? Function( RenamedWorkspaceOpenStep value)?  renamed,TResult? Function( ActivatedWorkspaceOpenStep value)?  activated,TResult? Function( NotStartedWorkspaceOpenStep value)?  notStarted,}){
final _that = this;
switch (_that) {
case OpenedWorkspaceOpenStep() when opened != null:
return opened(_that);case RenamedWorkspaceOpenStep() when renamed != null:
return renamed(_that);case ActivatedWorkspaceOpenStep() when activated != null:
return activated(_that);case NotStartedWorkspaceOpenStep() when notStarted != null:
return notStarted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OperationId operationId,  CommandResult<ProjectRecord> result)?  opened,TResult Function( OperationId operationId,  CommandResult<ProjectRecord> result)?  renamed,TResult Function( OperationId operationId,  CommandResult<Unit> result)?  activated,TResult Function( OperationId operationId,  WorkspaceOpenStage stage,  StudioFailure error)?  notStarted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case OpenedWorkspaceOpenStep() when opened != null:
return opened(_that.operationId,_that.result);case RenamedWorkspaceOpenStep() when renamed != null:
return renamed(_that.operationId,_that.result);case ActivatedWorkspaceOpenStep() when activated != null:
return activated(_that.operationId,_that.result);case NotStartedWorkspaceOpenStep() when notStarted != null:
return notStarted(_that.operationId,_that.stage,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OperationId operationId,  CommandResult<ProjectRecord> result)  opened,required TResult Function( OperationId operationId,  CommandResult<ProjectRecord> result)  renamed,required TResult Function( OperationId operationId,  CommandResult<Unit> result)  activated,required TResult Function( OperationId operationId,  WorkspaceOpenStage stage,  StudioFailure error)  notStarted,}) {final _that = this;
switch (_that) {
case OpenedWorkspaceOpenStep():
return opened(_that.operationId,_that.result);case RenamedWorkspaceOpenStep():
return renamed(_that.operationId,_that.result);case ActivatedWorkspaceOpenStep():
return activated(_that.operationId,_that.result);case NotStartedWorkspaceOpenStep():
return notStarted(_that.operationId,_that.stage,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OperationId operationId,  CommandResult<ProjectRecord> result)?  opened,TResult? Function( OperationId operationId,  CommandResult<ProjectRecord> result)?  renamed,TResult? Function( OperationId operationId,  CommandResult<Unit> result)?  activated,TResult? Function( OperationId operationId,  WorkspaceOpenStage stage,  StudioFailure error)?  notStarted,}) {final _that = this;
switch (_that) {
case OpenedWorkspaceOpenStep() when opened != null:
return opened(_that.operationId,_that.result);case RenamedWorkspaceOpenStep() when renamed != null:
return renamed(_that.operationId,_that.result);case ActivatedWorkspaceOpenStep() when activated != null:
return activated(_that.operationId,_that.result);case NotStartedWorkspaceOpenStep() when notStarted != null:
return notStarted(_that.operationId,_that.stage,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class OpenedWorkspaceOpenStep implements WorkspaceOpenStep {
  const OpenedWorkspaceOpenStep({required this.operationId, required this.result});


@override final  OperationId operationId;
 final  CommandResult<ProjectRecord> result;

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpenedWorkspaceOpenStepCopyWith<OpenedWorkspaceOpenStep> get copyWith => _$OpenedWorkspaceOpenStepCopyWithImpl<OpenedWorkspaceOpenStep>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is OpenedWorkspaceOpenStep&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,result);
}



}

/// @nodoc
abstract mixin class $OpenedWorkspaceOpenStepCopyWith<$Res> implements $WorkspaceOpenStepCopyWith<$Res> {
  factory $OpenedWorkspaceOpenStepCopyWith(OpenedWorkspaceOpenStep value, $Res Function(OpenedWorkspaceOpenStep) _then) = _$OpenedWorkspaceOpenStepCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, CommandResult<ProjectRecord> result
});


@override $OperationIdCopyWith<$Res> get operationId;$CommandResultCopyWith<ProjectRecord, $Res> get result;

}
/// @nodoc
class _$OpenedWorkspaceOpenStepCopyWithImpl<$Res>
    implements $OpenedWorkspaceOpenStepCopyWith<$Res> {
  _$OpenedWorkspaceOpenStepCopyWithImpl(this._self, this._then);

  final OpenedWorkspaceOpenStep _self;
  final $Res Function(OpenedWorkspaceOpenStep) _then;

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? result = null,}) {
  return _then(OpenedWorkspaceOpenStep(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CommandResult<ProjectRecord>,
  ));
}

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandResultCopyWith<ProjectRecord, $Res> get result {

  return $CommandResultCopyWith<ProjectRecord, $Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

/// @nodoc


class RenamedWorkspaceOpenStep implements WorkspaceOpenStep {
  const RenamedWorkspaceOpenStep({required this.operationId, required this.result});


@override final  OperationId operationId;
 final  CommandResult<ProjectRecord> result;

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RenamedWorkspaceOpenStepCopyWith<RenamedWorkspaceOpenStep> get copyWith => _$RenamedWorkspaceOpenStepCopyWithImpl<RenamedWorkspaceOpenStep>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RenamedWorkspaceOpenStep&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,result);
}



}

/// @nodoc
abstract mixin class $RenamedWorkspaceOpenStepCopyWith<$Res> implements $WorkspaceOpenStepCopyWith<$Res> {
  factory $RenamedWorkspaceOpenStepCopyWith(RenamedWorkspaceOpenStep value, $Res Function(RenamedWorkspaceOpenStep) _then) = _$RenamedWorkspaceOpenStepCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, CommandResult<ProjectRecord> result
});


@override $OperationIdCopyWith<$Res> get operationId;$CommandResultCopyWith<ProjectRecord, $Res> get result;

}
/// @nodoc
class _$RenamedWorkspaceOpenStepCopyWithImpl<$Res>
    implements $RenamedWorkspaceOpenStepCopyWith<$Res> {
  _$RenamedWorkspaceOpenStepCopyWithImpl(this._self, this._then);

  final RenamedWorkspaceOpenStep _self;
  final $Res Function(RenamedWorkspaceOpenStep) _then;

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? result = null,}) {
  return _then(RenamedWorkspaceOpenStep(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CommandResult<ProjectRecord>,
  ));
}

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandResultCopyWith<ProjectRecord, $Res> get result {

  return $CommandResultCopyWith<ProjectRecord, $Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

/// @nodoc


class ActivatedWorkspaceOpenStep implements WorkspaceOpenStep {
  const ActivatedWorkspaceOpenStep({required this.operationId, required this.result});


@override final  OperationId operationId;
 final  CommandResult<Unit> result;

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivatedWorkspaceOpenStepCopyWith<ActivatedWorkspaceOpenStep> get copyWith => _$ActivatedWorkspaceOpenStepCopyWithImpl<ActivatedWorkspaceOpenStep>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivatedWorkspaceOpenStep&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,result);
}



}

/// @nodoc
abstract mixin class $ActivatedWorkspaceOpenStepCopyWith<$Res> implements $WorkspaceOpenStepCopyWith<$Res> {
  factory $ActivatedWorkspaceOpenStepCopyWith(ActivatedWorkspaceOpenStep value, $Res Function(ActivatedWorkspaceOpenStep) _then) = _$ActivatedWorkspaceOpenStepCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, CommandResult<Unit> result
});


@override $OperationIdCopyWith<$Res> get operationId;$CommandResultCopyWith<Unit, $Res> get result;

}
/// @nodoc
class _$ActivatedWorkspaceOpenStepCopyWithImpl<$Res>
    implements $ActivatedWorkspaceOpenStepCopyWith<$Res> {
  _$ActivatedWorkspaceOpenStepCopyWithImpl(this._self, this._then);

  final ActivatedWorkspaceOpenStep _self;
  final $Res Function(ActivatedWorkspaceOpenStep) _then;

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? result = null,}) {
  return _then(ActivatedWorkspaceOpenStep(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CommandResult<Unit>,
  ));
}

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandResultCopyWith<Unit, $Res> get result {

  return $CommandResultCopyWith<Unit, $Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

/// @nodoc


class NotStartedWorkspaceOpenStep implements WorkspaceOpenStep {
  const NotStartedWorkspaceOpenStep({required this.operationId, required this.stage, required this.error});


@override final  OperationId operationId;
 final  WorkspaceOpenStage stage;
 final  StudioFailure error;

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NotStartedWorkspaceOpenStepCopyWith<NotStartedWorkspaceOpenStep> get copyWith => _$NotStartedWorkspaceOpenStepCopyWithImpl<NotStartedWorkspaceOpenStep>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NotStartedWorkspaceOpenStep&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,stage,error);
}



}

/// @nodoc
abstract mixin class $NotStartedWorkspaceOpenStepCopyWith<$Res> implements $WorkspaceOpenStepCopyWith<$Res> {
  factory $NotStartedWorkspaceOpenStepCopyWith(NotStartedWorkspaceOpenStep value, $Res Function(NotStartedWorkspaceOpenStep) _then) = _$NotStartedWorkspaceOpenStepCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, WorkspaceOpenStage stage, StudioFailure error
});


@override $OperationIdCopyWith<$Res> get operationId;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$NotStartedWorkspaceOpenStepCopyWithImpl<$Res>
    implements $NotStartedWorkspaceOpenStepCopyWith<$Res> {
  _$NotStartedWorkspaceOpenStepCopyWithImpl(this._self, this._then);

  final NotStartedWorkspaceOpenStep _self;
  final $Res Function(NotStartedWorkspaceOpenStep) _then;

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? stage = null,Object? error = null,}) {
  return _then(NotStartedWorkspaceOpenStep(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as WorkspaceOpenStage,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of WorkspaceOpenStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of WorkspaceOpenStep
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
mixin _$WorkspaceOpenSelection {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceOpenSelection);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $WorkspaceOpenSelectionCopyWith<$Res>  {
$WorkspaceOpenSelectionCopyWith(WorkspaceOpenSelection _, $Res Function(WorkspaceOpenSelection) __);
}


/// Adds pattern-matching-related methods to [WorkspaceOpenSelection].
extension WorkspaceOpenSelectionPatterns on WorkspaceOpenSelection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppliedWorkspaceOpenSelection value)?  applied,TResult Function( NotAttemptedWorkspaceOpenSelection value)?  notAttempted,TResult Function( FailedWorkspaceOpenSelection value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppliedWorkspaceOpenSelection() when applied != null:
return applied(_that);case NotAttemptedWorkspaceOpenSelection() when notAttempted != null:
return notAttempted(_that);case FailedWorkspaceOpenSelection() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppliedWorkspaceOpenSelection value)  applied,required TResult Function( NotAttemptedWorkspaceOpenSelection value)  notAttempted,required TResult Function( FailedWorkspaceOpenSelection value)  failed,}){
final _that = this;
switch (_that) {
case AppliedWorkspaceOpenSelection():
return applied(_that);case NotAttemptedWorkspaceOpenSelection():
return notAttempted(_that);case FailedWorkspaceOpenSelection():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppliedWorkspaceOpenSelection value)?  applied,TResult? Function( NotAttemptedWorkspaceOpenSelection value)?  notAttempted,TResult? Function( FailedWorkspaceOpenSelection value)?  failed,}){
final _that = this;
switch (_that) {
case AppliedWorkspaceOpenSelection() when applied != null:
return applied(_that);case NotAttemptedWorkspaceOpenSelection() when notAttempted != null:
return notAttempted(_that);case FailedWorkspaceOpenSelection() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( WorkspaceSelectionResult value)?  applied,TResult Function( StudioFailure reason)?  notAttempted,TResult Function( StudioFailure error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AppliedWorkspaceOpenSelection() when applied != null:
return applied(_that.value);case NotAttemptedWorkspaceOpenSelection() when notAttempted != null:
return notAttempted(_that.reason);case FailedWorkspaceOpenSelection() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( WorkspaceSelectionResult value)  applied,required TResult Function( StudioFailure reason)  notAttempted,required TResult Function( StudioFailure error)  failed,}) {final _that = this;
switch (_that) {
case AppliedWorkspaceOpenSelection():
return applied(_that.value);case NotAttemptedWorkspaceOpenSelection():
return notAttempted(_that.reason);case FailedWorkspaceOpenSelection():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( WorkspaceSelectionResult value)?  applied,TResult? Function( StudioFailure reason)?  notAttempted,TResult? Function( StudioFailure error)?  failed,}) {final _that = this;
switch (_that) {
case AppliedWorkspaceOpenSelection() when applied != null:
return applied(_that.value);case NotAttemptedWorkspaceOpenSelection() when notAttempted != null:
return notAttempted(_that.reason);case FailedWorkspaceOpenSelection() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class AppliedWorkspaceOpenSelection implements WorkspaceOpenSelection {
  const AppliedWorkspaceOpenSelection({required this.value});


 final  WorkspaceSelectionResult value;

/// Create a copy of WorkspaceOpenSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppliedWorkspaceOpenSelectionCopyWith<AppliedWorkspaceOpenSelection> get copyWith => _$AppliedWorkspaceOpenSelectionCopyWithImpl<AppliedWorkspaceOpenSelection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AppliedWorkspaceOpenSelection&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $AppliedWorkspaceOpenSelectionCopyWith<$Res> implements $WorkspaceOpenSelectionCopyWith<$Res> {
  factory $AppliedWorkspaceOpenSelectionCopyWith(AppliedWorkspaceOpenSelection value, $Res Function(AppliedWorkspaceOpenSelection) _then) = _$AppliedWorkspaceOpenSelectionCopyWithImpl;
@useResult
$Res call({
 WorkspaceSelectionResult value
});


$WorkspaceSelectionResultCopyWith<$Res> get value;

}
/// @nodoc
class _$AppliedWorkspaceOpenSelectionCopyWithImpl<$Res>
    implements $AppliedWorkspaceOpenSelectionCopyWith<$Res> {
  _$AppliedWorkspaceOpenSelectionCopyWithImpl(this._self, this._then);

  final AppliedWorkspaceOpenSelection _self;
  final $Res Function(AppliedWorkspaceOpenSelection) _then;

/// Create a copy of WorkspaceOpenSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(AppliedWorkspaceOpenSelection(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as WorkspaceSelectionResult,
  ));
}

/// Create a copy of WorkspaceOpenSelection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceSelectionResultCopyWith<$Res> get value {

  return $WorkspaceSelectionResultCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class NotAttemptedWorkspaceOpenSelection implements WorkspaceOpenSelection {
  const NotAttemptedWorkspaceOpenSelection({required this.reason});


 final  StudioFailure reason;

/// Create a copy of WorkspaceOpenSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NotAttemptedWorkspaceOpenSelectionCopyWith<NotAttemptedWorkspaceOpenSelection> get copyWith => _$NotAttemptedWorkspaceOpenSelectionCopyWithImpl<NotAttemptedWorkspaceOpenSelection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NotAttemptedWorkspaceOpenSelection&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}



}

/// @nodoc
abstract mixin class $NotAttemptedWorkspaceOpenSelectionCopyWith<$Res> implements $WorkspaceOpenSelectionCopyWith<$Res> {
  factory $NotAttemptedWorkspaceOpenSelectionCopyWith(NotAttemptedWorkspaceOpenSelection value, $Res Function(NotAttemptedWorkspaceOpenSelection) _then) = _$NotAttemptedWorkspaceOpenSelectionCopyWithImpl;
@useResult
$Res call({
 StudioFailure reason
});


$StudioFailureCopyWith<$Res> get reason;

}
/// @nodoc
class _$NotAttemptedWorkspaceOpenSelectionCopyWithImpl<$Res>
    implements $NotAttemptedWorkspaceOpenSelectionCopyWith<$Res> {
  _$NotAttemptedWorkspaceOpenSelectionCopyWithImpl(this._self, this._then);

  final NotAttemptedWorkspaceOpenSelection _self;
  final $Res Function(NotAttemptedWorkspaceOpenSelection) _then;

/// Create a copy of WorkspaceOpenSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(NotAttemptedWorkspaceOpenSelection(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of WorkspaceOpenSelection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get reason {

  return $StudioFailureCopyWith<$Res>(_self.reason, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}

/// @nodoc


class FailedWorkspaceOpenSelection implements WorkspaceOpenSelection {
  const FailedWorkspaceOpenSelection({required this.error});


 final  StudioFailure error;

/// Create a copy of WorkspaceOpenSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedWorkspaceOpenSelectionCopyWith<FailedWorkspaceOpenSelection> get copyWith => _$FailedWorkspaceOpenSelectionCopyWithImpl<FailedWorkspaceOpenSelection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedWorkspaceOpenSelection&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $FailedWorkspaceOpenSelectionCopyWith<$Res> implements $WorkspaceOpenSelectionCopyWith<$Res> {
  factory $FailedWorkspaceOpenSelectionCopyWith(FailedWorkspaceOpenSelection value, $Res Function(FailedWorkspaceOpenSelection) _then) = _$FailedWorkspaceOpenSelectionCopyWithImpl;
@useResult
$Res call({
 StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$FailedWorkspaceOpenSelectionCopyWithImpl<$Res>
    implements $FailedWorkspaceOpenSelectionCopyWith<$Res> {
  _$FailedWorkspaceOpenSelectionCopyWithImpl(this._self, this._then);

  final FailedWorkspaceOpenSelection _self;
  final $Res Function(FailedWorkspaceOpenSelection) _then;

/// Create a copy of WorkspaceOpenSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(FailedWorkspaceOpenSelection(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of WorkspaceOpenSelection
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
mixin _$WorkspaceOpenResult {


/// Create a copy of WorkspaceOpenResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceOpenResultCopyWith<WorkspaceOpenResult> get copyWith => _$WorkspaceOpenResultCopyWithImpl<WorkspaceOpenResult>(this as WorkspaceOpenResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceOpenResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceOpenResult&&const DeepCollectionEquality().equals(other.steps, _this.steps)&&(identical(other.selection, _this.selection) || other.selection == _this.selection));
}


@override
int get hashCode {
  final _this = this as WorkspaceOpenResult;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.steps),_this.selection);
}



}

/// @nodoc
abstract mixin class $WorkspaceOpenResultCopyWith<$Res>  {
  factory $WorkspaceOpenResultCopyWith(WorkspaceOpenResult value, $Res Function(WorkspaceOpenResult) _then) = _$WorkspaceOpenResultCopyWithImpl;
@useResult
$Res call({
 List<WorkspaceOpenStep> steps, WorkspaceOpenSelection selection
});


$WorkspaceOpenSelectionCopyWith<$Res> get selection;

}
/// @nodoc
class _$WorkspaceOpenResultCopyWithImpl<$Res>
    implements $WorkspaceOpenResultCopyWith<$Res> {
  _$WorkspaceOpenResultCopyWithImpl(this._self, this._then);

  final WorkspaceOpenResult _self;
  final $Res Function(WorkspaceOpenResult) _then;

/// Create a copy of WorkspaceOpenResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? steps = null,Object? selection = null,}) {
  return _then(WorkspaceOpenResult(
steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<WorkspaceOpenStep>,selection: null == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as WorkspaceOpenSelection,
  ));
}
/// Create a copy of WorkspaceOpenResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceOpenSelectionCopyWith<$Res> get selection {

  return $WorkspaceOpenSelectionCopyWith<$Res>(_self.selection, (value) {
    return _then(_self.copyWith(selection: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceOpenResult].
extension WorkspaceOpenResultPatterns on WorkspaceOpenResult {
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
