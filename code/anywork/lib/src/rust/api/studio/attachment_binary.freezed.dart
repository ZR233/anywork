// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'attachment_binary.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAttachmentBinaryTarget {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAttachmentBinaryTarget);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAttachmentBinaryTarget()';
}


}

/// @nodoc
class $BridgeAttachmentBinaryTargetCopyWith<$Res>  {
$BridgeAttachmentBinaryTargetCopyWith(BridgeAttachmentBinaryTarget _, $Res Function(BridgeAttachmentBinaryTarget) __);
}


/// Adds pattern-matching-related methods to [BridgeAttachmentBinaryTarget].
extension BridgeAttachmentBinaryTargetPatterns on BridgeAttachmentBinaryTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAttachmentBinaryTarget_Draft value)?  draft,TResult Function( BridgeAttachmentBinaryTarget_Thread value)?  thread,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAttachmentBinaryTarget_Draft() when draft != null:
return draft(_that);case BridgeAttachmentBinaryTarget_Thread() when thread != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAttachmentBinaryTarget_Draft value)  draft,required TResult Function( BridgeAttachmentBinaryTarget_Thread value)  thread,}){
final _that = this;
switch (_that) {
case BridgeAttachmentBinaryTarget_Draft():
return draft(_that);case BridgeAttachmentBinaryTarget_Thread():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAttachmentBinaryTarget_Draft value)?  draft,TResult? Function( BridgeAttachmentBinaryTarget_Thread value)?  thread,}){
final _that = this;
switch (_that) {
case BridgeAttachmentBinaryTarget_Draft() when draft != null:
return draft(_that);case BridgeAttachmentBinaryTarget_Thread() when thread != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String draftId)?  draft,TResult Function( String threadId,  String attachmentId)?  thread,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAttachmentBinaryTarget_Draft() when draft != null:
return draft(_that.draftId);case BridgeAttachmentBinaryTarget_Thread() when thread != null:
return thread(_that.threadId,_that.attachmentId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String draftId)  draft,required TResult Function( String threadId,  String attachmentId)  thread,}) {final _that = this;
switch (_that) {
case BridgeAttachmentBinaryTarget_Draft():
return draft(_that.draftId);case BridgeAttachmentBinaryTarget_Thread():
return thread(_that.threadId,_that.attachmentId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String draftId)?  draft,TResult? Function( String threadId,  String attachmentId)?  thread,}) {final _that = this;
switch (_that) {
case BridgeAttachmentBinaryTarget_Draft() when draft != null:
return draft(_that.draftId);case BridgeAttachmentBinaryTarget_Thread() when thread != null:
return thread(_that.threadId,_that.attachmentId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAttachmentBinaryTarget_Draft extends BridgeAttachmentBinaryTarget {
  const BridgeAttachmentBinaryTarget_Draft({required this.draftId}): super._();


 final  String draftId;

/// Create a copy of BridgeAttachmentBinaryTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAttachmentBinaryTarget_DraftCopyWith<BridgeAttachmentBinaryTarget_Draft> get copyWith => _$BridgeAttachmentBinaryTarget_DraftCopyWithImpl<BridgeAttachmentBinaryTarget_Draft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAttachmentBinaryTarget_Draft&&(identical(other.draftId, draftId) || other.draftId == draftId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,draftId);
}

@override
String toString() {
    return 'BridgeAttachmentBinaryTarget.draft(draftId: $draftId)';
}


}

/// @nodoc
abstract mixin class $BridgeAttachmentBinaryTarget_DraftCopyWith<$Res> implements $BridgeAttachmentBinaryTargetCopyWith<$Res> {
  factory $BridgeAttachmentBinaryTarget_DraftCopyWith(BridgeAttachmentBinaryTarget_Draft value, $Res Function(BridgeAttachmentBinaryTarget_Draft) _then) = _$BridgeAttachmentBinaryTarget_DraftCopyWithImpl;
@useResult
$Res call({
 String draftId
});




}
/// @nodoc
class _$BridgeAttachmentBinaryTarget_DraftCopyWithImpl<$Res>
    implements $BridgeAttachmentBinaryTarget_DraftCopyWith<$Res> {
  _$BridgeAttachmentBinaryTarget_DraftCopyWithImpl(this._self, this._then);

  final BridgeAttachmentBinaryTarget_Draft _self;
  final $Res Function(BridgeAttachmentBinaryTarget_Draft) _then;

/// Create a copy of BridgeAttachmentBinaryTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? draftId = null,}) {
  return _then(BridgeAttachmentBinaryTarget_Draft(
draftId: null == draftId ? _self.draftId : draftId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAttachmentBinaryTarget_Thread extends BridgeAttachmentBinaryTarget {
  const BridgeAttachmentBinaryTarget_Thread({required this.threadId, required this.attachmentId}): super._();


 final  String threadId;
 final  String attachmentId;

/// Create a copy of BridgeAttachmentBinaryTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAttachmentBinaryTarget_ThreadCopyWith<BridgeAttachmentBinaryTarget_Thread> get copyWith => _$BridgeAttachmentBinaryTarget_ThreadCopyWithImpl<BridgeAttachmentBinaryTarget_Thread>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAttachmentBinaryTarget_Thread&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.attachmentId, attachmentId) || other.attachmentId == attachmentId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,attachmentId);
}

@override
String toString() {
    return 'BridgeAttachmentBinaryTarget.thread(threadId: $threadId, attachmentId: $attachmentId)';
}


}

/// @nodoc
abstract mixin class $BridgeAttachmentBinaryTarget_ThreadCopyWith<$Res> implements $BridgeAttachmentBinaryTargetCopyWith<$Res> {
  factory $BridgeAttachmentBinaryTarget_ThreadCopyWith(BridgeAttachmentBinaryTarget_Thread value, $Res Function(BridgeAttachmentBinaryTarget_Thread) _then) = _$BridgeAttachmentBinaryTarget_ThreadCopyWithImpl;
@useResult
$Res call({
 String threadId, String attachmentId
});




}
/// @nodoc
class _$BridgeAttachmentBinaryTarget_ThreadCopyWithImpl<$Res>
    implements $BridgeAttachmentBinaryTarget_ThreadCopyWith<$Res> {
  _$BridgeAttachmentBinaryTarget_ThreadCopyWithImpl(this._self, this._then);

  final BridgeAttachmentBinaryTarget_Thread _self;
  final $Res Function(BridgeAttachmentBinaryTarget_Thread) _then;

/// Create a copy of BridgeAttachmentBinaryTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? attachmentId = null,}) {
  return _then(BridgeAttachmentBinaryTarget_Thread(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,attachmentId: null == attachmentId ? _self.attachmentId : attachmentId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
