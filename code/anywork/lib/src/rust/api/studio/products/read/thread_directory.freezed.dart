// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_directory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeThreadDirectoryScope {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryScope);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadDirectoryScope()';
}


}

/// @nodoc
class $BridgeThreadDirectoryScopeCopyWith<$Res>  {
$BridgeThreadDirectoryScopeCopyWith(BridgeThreadDirectoryScope _, $Res Function(BridgeThreadDirectoryScope) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadDirectoryScope].
extension BridgeThreadDirectoryScopePatterns on BridgeThreadDirectoryScope {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadDirectoryScope_Query value)?  query,TResult Function( BridgeThreadDirectoryScope_Thread value)?  thread,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadDirectoryScope_Query() when query != null:
return query(_that);case BridgeThreadDirectoryScope_Thread() when thread != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadDirectoryScope_Query value)  query,required TResult Function( BridgeThreadDirectoryScope_Thread value)  thread,}){
final _that = this;
switch (_that) {
case BridgeThreadDirectoryScope_Query():
return query(_that);case BridgeThreadDirectoryScope_Thread():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadDirectoryScope_Query value)?  query,TResult? Function( BridgeThreadDirectoryScope_Thread value)?  thread,}){
final _that = this;
switch (_that) {
case BridgeThreadDirectoryScope_Query() when query != null:
return query(_that);case BridgeThreadDirectoryScope_Thread() when thread != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadDirectoryQuery query,  bool includePinned)?  query,TResult Function( String threadId)?  thread,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadDirectoryScope_Query() when query != null:
return query(_that.query,_that.includePinned);case BridgeThreadDirectoryScope_Thread() when thread != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadDirectoryQuery query,  bool includePinned)  query,required TResult Function( String threadId)  thread,}) {final _that = this;
switch (_that) {
case BridgeThreadDirectoryScope_Query():
return query(_that.query,_that.includePinned);case BridgeThreadDirectoryScope_Thread():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadDirectoryQuery query,  bool includePinned)?  query,TResult? Function( String threadId)?  thread,}) {final _that = this;
switch (_that) {
case BridgeThreadDirectoryScope_Query() when query != null:
return query(_that.query,_that.includePinned);case BridgeThreadDirectoryScope_Thread() when thread != null:
return thread(_that.threadId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadDirectoryScope_Query extends BridgeThreadDirectoryScope {
  const BridgeThreadDirectoryScope_Query({required this.query, required this.includePinned}): super._();


 final  BridgeThreadDirectoryQuery query;
 final  bool includePinned;

/// Create a copy of BridgeThreadDirectoryScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryScope_QueryCopyWith<BridgeThreadDirectoryScope_Query> get copyWith => _$BridgeThreadDirectoryScope_QueryCopyWithImpl<BridgeThreadDirectoryScope_Query>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryScope_Query&&(identical(other.query, query) || other.query == query)&&(identical(other.includePinned, includePinned) || other.includePinned == includePinned));
}


@override
int get hashCode {
    return Object.hash(runtimeType,query,includePinned);
}

@override
String toString() {
    return 'BridgeThreadDirectoryScope.query(query: $query, includePinned: $includePinned)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadDirectoryScope_QueryCopyWith<$Res> implements $BridgeThreadDirectoryScopeCopyWith<$Res> {
  factory $BridgeThreadDirectoryScope_QueryCopyWith(BridgeThreadDirectoryScope_Query value, $Res Function(BridgeThreadDirectoryScope_Query) _then) = _$BridgeThreadDirectoryScope_QueryCopyWithImpl;
@useResult
$Res call({
 BridgeThreadDirectoryQuery query, bool includePinned
});




}
/// @nodoc
class _$BridgeThreadDirectoryScope_QueryCopyWithImpl<$Res>
    implements $BridgeThreadDirectoryScope_QueryCopyWith<$Res> {
  _$BridgeThreadDirectoryScope_QueryCopyWithImpl(this._self, this._then);

  final BridgeThreadDirectoryScope_Query _self;
  final $Res Function(BridgeThreadDirectoryScope_Query) _then;

/// Create a copy of BridgeThreadDirectoryScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,Object? includePinned = null,}) {
  return _then(BridgeThreadDirectoryScope_Query(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as BridgeThreadDirectoryQuery,includePinned: null == includePinned ? _self.includePinned : includePinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeThreadDirectoryScope_Thread extends BridgeThreadDirectoryScope {
  const BridgeThreadDirectoryScope_Thread({required this.threadId}): super._();


 final  String threadId;

/// Create a copy of BridgeThreadDirectoryScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadDirectoryScope_ThreadCopyWith<BridgeThreadDirectoryScope_Thread> get copyWith => _$BridgeThreadDirectoryScope_ThreadCopyWithImpl<BridgeThreadDirectoryScope_Thread>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadDirectoryScope_Thread&&(identical(other.threadId, threadId) || other.threadId == threadId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId);
}

@override
String toString() {
    return 'BridgeThreadDirectoryScope.thread(threadId: $threadId)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadDirectoryScope_ThreadCopyWith<$Res> implements $BridgeThreadDirectoryScopeCopyWith<$Res> {
  factory $BridgeThreadDirectoryScope_ThreadCopyWith(BridgeThreadDirectoryScope_Thread value, $Res Function(BridgeThreadDirectoryScope_Thread) _then) = _$BridgeThreadDirectoryScope_ThreadCopyWithImpl;
@useResult
$Res call({
 String threadId
});




}
/// @nodoc
class _$BridgeThreadDirectoryScope_ThreadCopyWithImpl<$Res>
    implements $BridgeThreadDirectoryScope_ThreadCopyWith<$Res> {
  _$BridgeThreadDirectoryScope_ThreadCopyWithImpl(this._self, this._then);

  final BridgeThreadDirectoryScope_Thread _self;
  final $Res Function(BridgeThreadDirectoryScope_Thread) _then;

/// Create a copy of BridgeThreadDirectoryScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? threadId = null,}) {
  return _then(BridgeThreadDirectoryScope_Thread(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
