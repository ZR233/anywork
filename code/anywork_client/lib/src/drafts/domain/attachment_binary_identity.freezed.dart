// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'attachment_binary_identity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AttachmentBinaryIdentity {

 String get scopeId; String get runtimeEpoch; int get incarnation; AttachmentBinaryTarget get target;
/// Create a copy of AttachmentBinaryIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttachmentBinaryIdentityCopyWith<AttachmentBinaryIdentity> get copyWith => _$AttachmentBinaryIdentityCopyWithImpl<AttachmentBinaryIdentity>(this as AttachmentBinaryIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AttachmentBinaryIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AttachmentBinaryIdentity&&(identical(other.scopeId, _this.scopeId) || other.scopeId == _this.scopeId)&&(identical(other.runtimeEpoch, _this.runtimeEpoch) || other.runtimeEpoch == _this.runtimeEpoch)&&(identical(other.incarnation, _this.incarnation) || other.incarnation == _this.incarnation)&&(identical(other.target, _this.target) || other.target == _this.target));
}


@override
int get hashCode {
  final _this = this as AttachmentBinaryIdentity;
  return Object.hash(runtimeType,_this.scopeId,_this.runtimeEpoch,_this.incarnation,_this.target);
}



}

/// @nodoc
abstract mixin class $AttachmentBinaryIdentityCopyWith<$Res>  {
  factory $AttachmentBinaryIdentityCopyWith(AttachmentBinaryIdentity value, $Res Function(AttachmentBinaryIdentity) _then) = _$AttachmentBinaryIdentityCopyWithImpl;
@useResult
$Res call({
 String scopeId, String runtimeEpoch, int incarnation, AttachmentBinaryTarget target
});


$AttachmentBinaryTargetCopyWith<$Res> get target;

}
/// @nodoc
class _$AttachmentBinaryIdentityCopyWithImpl<$Res>
    implements $AttachmentBinaryIdentityCopyWith<$Res> {
  _$AttachmentBinaryIdentityCopyWithImpl(this._self, this._then);

  final AttachmentBinaryIdentity _self;
  final $Res Function(AttachmentBinaryIdentity) _then;

/// Create a copy of AttachmentBinaryIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scopeId = null,Object? runtimeEpoch = null,Object? incarnation = null,Object? target = null,}) {
  return _then(AttachmentBinaryIdentity(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AttachmentBinaryTarget,
  ));
}
/// Create a copy of AttachmentBinaryIdentity
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AttachmentBinaryTargetCopyWith<$Res> get target {

  return $AttachmentBinaryTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}


/// Adds pattern-matching-related methods to [AttachmentBinaryIdentity].
extension AttachmentBinaryIdentityPatterns on AttachmentBinaryIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AttachmentBinaryIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AttachmentBinaryIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AttachmentBinaryIdentity value)  $default,){
final _that = this;
switch (_that) {
case _AttachmentBinaryIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AttachmentBinaryIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _AttachmentBinaryIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String scopeId,  String runtimeEpoch,  int incarnation,  AttachmentBinaryTarget target)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AttachmentBinaryIdentity() when $default != null:
return $default(_that.scopeId,_that.runtimeEpoch,_that.incarnation,_that.target);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String scopeId,  String runtimeEpoch,  int incarnation,  AttachmentBinaryTarget target)  $default,) {final _that = this;
switch (_that) {
case _AttachmentBinaryIdentity():
return $default(_that.scopeId,_that.runtimeEpoch,_that.incarnation,_that.target);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String scopeId,  String runtimeEpoch,  int incarnation,  AttachmentBinaryTarget target)?  $default,) {final _that = this;
switch (_that) {
case _AttachmentBinaryIdentity() when $default != null:
return $default(_that.scopeId,_that.runtimeEpoch,_that.incarnation,_that.target);case _:
  return null;

}
}

}

/// @nodoc


class _AttachmentBinaryIdentity implements AttachmentBinaryIdentity {
  const _AttachmentBinaryIdentity({required this.scopeId, required this.runtimeEpoch, required this.incarnation, required this.target});


@override final  String scopeId;
@override final  String runtimeEpoch;
@override final  int incarnation;
@override final  AttachmentBinaryTarget target;

/// Create a copy of AttachmentBinaryIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AttachmentBinaryIdentityCopyWith<_AttachmentBinaryIdentity> get copyWith => __$AttachmentBinaryIdentityCopyWithImpl<_AttachmentBinaryIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AttachmentBinaryIdentity&&(identical(other.scopeId, scopeId) || other.scopeId == scopeId)&&(identical(other.runtimeEpoch, runtimeEpoch) || other.runtimeEpoch == runtimeEpoch)&&(identical(other.incarnation, incarnation) || other.incarnation == incarnation)&&(identical(other.target, target) || other.target == target));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scopeId,runtimeEpoch,incarnation,target);
}



}

/// @nodoc
abstract mixin class _$AttachmentBinaryIdentityCopyWith<$Res> implements $AttachmentBinaryIdentityCopyWith<$Res> {
  factory _$AttachmentBinaryIdentityCopyWith(_AttachmentBinaryIdentity value, $Res Function(_AttachmentBinaryIdentity) _then) = __$AttachmentBinaryIdentityCopyWithImpl;
@override @useResult
$Res call({
 String scopeId, String runtimeEpoch, int incarnation, AttachmentBinaryTarget target
});


@override $AttachmentBinaryTargetCopyWith<$Res> get target;

}
/// @nodoc
class __$AttachmentBinaryIdentityCopyWithImpl<$Res>
    implements _$AttachmentBinaryIdentityCopyWith<$Res> {
  __$AttachmentBinaryIdentityCopyWithImpl(this._self, this._then);

  final _AttachmentBinaryIdentity _self;
  final $Res Function(_AttachmentBinaryIdentity) _then;

/// Create a copy of AttachmentBinaryIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scopeId = null,Object? runtimeEpoch = null,Object? incarnation = null,Object? target = null,}) {
  return _then(_AttachmentBinaryIdentity(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AttachmentBinaryTarget,
  ));
}

/// Create a copy of AttachmentBinaryIdentity
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AttachmentBinaryTargetCopyWith<$Res> get target {

  return $AttachmentBinaryTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}

/// @nodoc
mixin _$AttachmentBinaryTarget {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttachmentBinaryTarget);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AttachmentBinaryTargetCopyWith<$Res>  {
$AttachmentBinaryTargetCopyWith(AttachmentBinaryTarget _, $Res Function(AttachmentBinaryTarget) __);
}


/// Adds pattern-matching-related methods to [AttachmentBinaryTarget].
extension AttachmentBinaryTargetPatterns on AttachmentBinaryTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DraftAttachmentBinaryTarget value)?  draft,TResult Function( ThreadAttachmentBinaryTarget value)?  thread,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DraftAttachmentBinaryTarget() when draft != null:
return draft(_that);case ThreadAttachmentBinaryTarget() when thread != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DraftAttachmentBinaryTarget value)  draft,required TResult Function( ThreadAttachmentBinaryTarget value)  thread,}){
final _that = this;
switch (_that) {
case DraftAttachmentBinaryTarget():
return draft(_that);case ThreadAttachmentBinaryTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DraftAttachmentBinaryTarget value)?  draft,TResult? Function( ThreadAttachmentBinaryTarget value)?  thread,}){
final _that = this;
switch (_that) {
case DraftAttachmentBinaryTarget() when draft != null:
return draft(_that);case ThreadAttachmentBinaryTarget() when thread != null:
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
case DraftAttachmentBinaryTarget() when draft != null:
return draft(_that.draftId);case ThreadAttachmentBinaryTarget() when thread != null:
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
case DraftAttachmentBinaryTarget():
return draft(_that.draftId);case ThreadAttachmentBinaryTarget():
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
case DraftAttachmentBinaryTarget() when draft != null:
return draft(_that.draftId);case ThreadAttachmentBinaryTarget() when thread != null:
return thread(_that.threadId,_that.attachmentId);case _:
  return null;

}
}

}

/// @nodoc


class DraftAttachmentBinaryTarget implements AttachmentBinaryTarget {
  const DraftAttachmentBinaryTarget({required this.draftId});


 final  String draftId;

/// Create a copy of AttachmentBinaryTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DraftAttachmentBinaryTargetCopyWith<DraftAttachmentBinaryTarget> get copyWith => _$DraftAttachmentBinaryTargetCopyWithImpl<DraftAttachmentBinaryTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftAttachmentBinaryTarget&&(identical(other.draftId, draftId) || other.draftId == draftId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,draftId);
}



}

/// @nodoc
abstract mixin class $DraftAttachmentBinaryTargetCopyWith<$Res> implements $AttachmentBinaryTargetCopyWith<$Res> {
  factory $DraftAttachmentBinaryTargetCopyWith(DraftAttachmentBinaryTarget value, $Res Function(DraftAttachmentBinaryTarget) _then) = _$DraftAttachmentBinaryTargetCopyWithImpl;
@useResult
$Res call({
 String draftId
});




}
/// @nodoc
class _$DraftAttachmentBinaryTargetCopyWithImpl<$Res>
    implements $DraftAttachmentBinaryTargetCopyWith<$Res> {
  _$DraftAttachmentBinaryTargetCopyWithImpl(this._self, this._then);

  final DraftAttachmentBinaryTarget _self;
  final $Res Function(DraftAttachmentBinaryTarget) _then;

/// Create a copy of AttachmentBinaryTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? draftId = null,}) {
  return _then(DraftAttachmentBinaryTarget(
draftId: null == draftId ? _self.draftId : draftId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ThreadAttachmentBinaryTarget implements AttachmentBinaryTarget {
  const ThreadAttachmentBinaryTarget({required this.threadId, required this.attachmentId});


 final  String threadId;
 final  String attachmentId;

/// Create a copy of AttachmentBinaryTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAttachmentBinaryTargetCopyWith<ThreadAttachmentBinaryTarget> get copyWith => _$ThreadAttachmentBinaryTargetCopyWithImpl<ThreadAttachmentBinaryTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAttachmentBinaryTarget&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.attachmentId, attachmentId) || other.attachmentId == attachmentId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,attachmentId);
}



}

/// @nodoc
abstract mixin class $ThreadAttachmentBinaryTargetCopyWith<$Res> implements $AttachmentBinaryTargetCopyWith<$Res> {
  factory $ThreadAttachmentBinaryTargetCopyWith(ThreadAttachmentBinaryTarget value, $Res Function(ThreadAttachmentBinaryTarget) _then) = _$ThreadAttachmentBinaryTargetCopyWithImpl;
@useResult
$Res call({
 String threadId, String attachmentId
});




}
/// @nodoc
class _$ThreadAttachmentBinaryTargetCopyWithImpl<$Res>
    implements $ThreadAttachmentBinaryTargetCopyWith<$Res> {
  _$ThreadAttachmentBinaryTargetCopyWithImpl(this._self, this._then);

  final ThreadAttachmentBinaryTarget _self;
  final $Res Function(ThreadAttachmentBinaryTarget) _then;

/// Create a copy of AttachmentBinaryTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? attachmentId = null,}) {
  return _then(ThreadAttachmentBinaryTarget(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,attachmentId: null == attachmentId ? _self.attachmentId : attachmentId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
