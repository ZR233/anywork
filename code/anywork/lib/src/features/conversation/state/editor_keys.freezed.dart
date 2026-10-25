// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'editor_keys.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ComposerKey {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ComposerKey);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ComposerKey()';
}


}

/// @nodoc
class $ComposerKeyCopyWith<$Res>  {
$ComposerKeyCopyWith(ComposerKey _, $Res Function(ComposerKey) __);
}


/// Adds pattern-matching-related methods to [ComposerKey].
extension ComposerKeyPatterns on ComposerKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StartComposerKey value)?  start,TResult Function( ThreadComposerKey value)?  thread,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StartComposerKey() when start != null:
return start(_that);case ThreadComposerKey() when thread != null:
return thread(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StartComposerKey value)  start,required TResult Function( ThreadComposerKey value)  thread,}){
final _that = this;
switch (_that) {
case StartComposerKey():
return start(_that);case ThreadComposerKey():
return thread(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StartComposerKey value)?  start,TResult? Function( ThreadComposerKey value)?  thread,}){
final _that = this;
switch (_that) {
case StartComposerKey() when start != null:
return start(_that);case ThreadComposerKey() when thread != null:
return thread(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String projectId)?  start,TResult Function( String threadId)?  thread,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StartComposerKey() when start != null:
return start(_that.projectId);case ThreadComposerKey() when thread != null:
return thread(_that.threadId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String projectId)  start,required TResult Function( String threadId)  thread,}) {final _that = this;
switch (_that) {
case StartComposerKey():
return start(_that.projectId);case ThreadComposerKey():
return thread(_that.threadId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String projectId)?  start,TResult? Function( String threadId)?  thread,}) {final _that = this;
switch (_that) {
case StartComposerKey() when start != null:
return start(_that.projectId);case ThreadComposerKey() when thread != null:
return thread(_that.threadId);case _:
  return null;

}
}

}

/// @nodoc


class StartComposerKey implements ComposerKey {
  const StartComposerKey({required this.projectId});


 final  String projectId;

/// Create a copy of ComposerKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartComposerKeyCopyWith<StartComposerKey> get copyWith => _$StartComposerKeyCopyWithImpl<StartComposerKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StartComposerKey&&(identical(other.projectId, projectId) || other.projectId == projectId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId);
}

@override
String toString() {
    return 'ComposerKey.start(projectId: $projectId)';
}


}

/// @nodoc
abstract mixin class $StartComposerKeyCopyWith<$Res> implements $ComposerKeyCopyWith<$Res> {
  factory $StartComposerKeyCopyWith(StartComposerKey value, $Res Function(StartComposerKey) _then) = _$StartComposerKeyCopyWithImpl;
@useResult
$Res call({
 String projectId
});




}
/// @nodoc
class _$StartComposerKeyCopyWithImpl<$Res>
    implements $StartComposerKeyCopyWith<$Res> {
  _$StartComposerKeyCopyWithImpl(this._self, this._then);

  final StartComposerKey _self;
  final $Res Function(StartComposerKey) _then;

/// Create a copy of ComposerKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? projectId = null,}) {
  return _then(StartComposerKey(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ThreadComposerKey implements ComposerKey {
  const ThreadComposerKey({required this.threadId});


 final  String threadId;

/// Create a copy of ComposerKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadComposerKeyCopyWith<ThreadComposerKey> get copyWith => _$ThreadComposerKeyCopyWithImpl<ThreadComposerKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadComposerKey&&(identical(other.threadId, threadId) || other.threadId == threadId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId);
}

@override
String toString() {
    return 'ComposerKey.thread(threadId: $threadId)';
}


}

/// @nodoc
abstract mixin class $ThreadComposerKeyCopyWith<$Res> implements $ComposerKeyCopyWith<$Res> {
  factory $ThreadComposerKeyCopyWith(ThreadComposerKey value, $Res Function(ThreadComposerKey) _then) = _$ThreadComposerKeyCopyWithImpl;
@useResult
$Res call({
 String threadId
});




}
/// @nodoc
class _$ThreadComposerKeyCopyWithImpl<$Res>
    implements $ThreadComposerKeyCopyWith<$Res> {
  _$ThreadComposerKeyCopyWithImpl(this._self, this._then);

  final ThreadComposerKey _self;
  final $Res Function(ThreadComposerKey) _then;

/// Create a copy of ComposerKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? threadId = null,}) {
  return _then(ThreadComposerKey(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$InteractionEditorKey {

 String get threadId; int get incarnation; String get interactionId; int get revision;
/// Create a copy of InteractionEditorKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionEditorKeyCopyWith<InteractionEditorKey> get copyWith => _$InteractionEditorKeyCopyWithImpl<InteractionEditorKey>(this as InteractionEditorKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionEditorKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionEditorKey&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.incarnation, _this.incarnation) || other.incarnation == _this.incarnation)&&(identical(other.interactionId, _this.interactionId) || other.interactionId == _this.interactionId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as InteractionEditorKey;
  return Object.hash(runtimeType,_this.threadId,_this.incarnation,_this.interactionId,_this.revision);
}

@override
String toString() {
  final _this = this as InteractionEditorKey;
  return 'InteractionEditorKey(threadId: ${_this.threadId}, incarnation: ${_this.incarnation}, interactionId: ${_this.interactionId}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $InteractionEditorKeyCopyWith<$Res>  {
  factory $InteractionEditorKeyCopyWith(InteractionEditorKey value, $Res Function(InteractionEditorKey) _then) = _$InteractionEditorKeyCopyWithImpl;
@useResult
$Res call({
 String threadId, int incarnation, String interactionId, int revision
});




}
/// @nodoc
class _$InteractionEditorKeyCopyWithImpl<$Res>
    implements $InteractionEditorKeyCopyWith<$Res> {
  _$InteractionEditorKeyCopyWithImpl(this._self, this._then);

  final InteractionEditorKey _self;
  final $Res Function(InteractionEditorKey) _then;

/// Create a copy of InteractionEditorKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? incarnation = null,Object? interactionId = null,Object? revision = null,}) {
  return _then(InteractionEditorKey(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [InteractionEditorKey].
extension InteractionEditorKeyPatterns on InteractionEditorKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionEditorKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionEditorKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionEditorKey value)  $default,){
final _that = this;
switch (_that) {
case _InteractionEditorKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionEditorKey value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionEditorKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  int incarnation,  String interactionId,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionEditorKey() when $default != null:
return $default(_that.threadId,_that.incarnation,_that.interactionId,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  int incarnation,  String interactionId,  int revision)  $default,) {final _that = this;
switch (_that) {
case _InteractionEditorKey():
return $default(_that.threadId,_that.incarnation,_that.interactionId,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  int incarnation,  String interactionId,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _InteractionEditorKey() when $default != null:
return $default(_that.threadId,_that.incarnation,_that.interactionId,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionEditorKey implements InteractionEditorKey {
  const _InteractionEditorKey({required this.threadId, required this.incarnation, required this.interactionId, required this.revision});


@override final  String threadId;
@override final  int incarnation;
@override final  String interactionId;
@override final  int revision;

/// Create a copy of InteractionEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionEditorKeyCopyWith<_InteractionEditorKey> get copyWith => __$InteractionEditorKeyCopyWithImpl<_InteractionEditorKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionEditorKey&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.incarnation, incarnation) || other.incarnation == incarnation)&&(identical(other.interactionId, interactionId) || other.interactionId == interactionId)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,incarnation,interactionId,revision);
}

@override
String toString() {
    return 'InteractionEditorKey(threadId: $threadId, incarnation: $incarnation, interactionId: $interactionId, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$InteractionEditorKeyCopyWith<$Res> implements $InteractionEditorKeyCopyWith<$Res> {
  factory _$InteractionEditorKeyCopyWith(_InteractionEditorKey value, $Res Function(_InteractionEditorKey) _then) = __$InteractionEditorKeyCopyWithImpl;
@override @useResult
$Res call({
 String threadId, int incarnation, String interactionId, int revision
});




}
/// @nodoc
class __$InteractionEditorKeyCopyWithImpl<$Res>
    implements _$InteractionEditorKeyCopyWith<$Res> {
  __$InteractionEditorKeyCopyWithImpl(this._self, this._then);

  final _InteractionEditorKey _self;
  final $Res Function(_InteractionEditorKey) _then;

/// Create a copy of InteractionEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? incarnation = null,Object? interactionId = null,Object? revision = null,}) {
  return _then(_InteractionEditorKey(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
