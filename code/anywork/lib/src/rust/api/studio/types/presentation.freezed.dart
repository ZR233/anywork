// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'presentation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeCurrentFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeCurrentFrame()';
}


}

/// @nodoc
class $BridgeCurrentFrameCopyWith<$Res>  {
$BridgeCurrentFrameCopyWith(BridgeCurrentFrame _, $Res Function(BridgeCurrentFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeCurrentFrame].
extension BridgeCurrentFramePatterns on BridgeCurrentFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeCurrentFrame_Reset value)?  reset,TResult Function( BridgeCurrentFrame_Notification value)?  notification,TResult Function( BridgeCurrentFrame_Projection value)?  projection,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeCurrentFrame_Reset() when reset != null:
return reset(_that);case BridgeCurrentFrame_Notification() when notification != null:
return notification(_that);case BridgeCurrentFrame_Projection() when projection != null:
return projection(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeCurrentFrame_Reset value)  reset,required TResult Function( BridgeCurrentFrame_Notification value)  notification,required TResult Function( BridgeCurrentFrame_Projection value)  projection,}){
final _that = this;
switch (_that) {
case BridgeCurrentFrame_Reset():
return reset(_that);case BridgeCurrentFrame_Notification():
return notification(_that);case BridgeCurrentFrame_Projection():
return projection(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeCurrentFrame_Reset value)?  reset,TResult? Function( BridgeCurrentFrame_Notification value)?  notification,TResult? Function( BridgeCurrentFrame_Projection value)?  projection,}){
final _that = this;
switch (_that) {
case BridgeCurrentFrame_Reset() when reset != null:
return reset(_that);case BridgeCurrentFrame_Notification() when notification != null:
return notification(_that);case BridgeCurrentFrame_Projection() when projection != null:
return projection(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeCurrentView view)?  reset,TResult Function( BridgeCurrentRevision revision,  BridgeThreadNotificationEnvelope notification)?  notification,TResult Function( BridgeCurrentRevision revision,  BridgeCurrentProjection projection)?  projection,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeCurrentFrame_Reset() when reset != null:
return reset(_that.view);case BridgeCurrentFrame_Notification() when notification != null:
return notification(_that.revision,_that.notification);case BridgeCurrentFrame_Projection() when projection != null:
return projection(_that.revision,_that.projection);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeCurrentView view)  reset,required TResult Function( BridgeCurrentRevision revision,  BridgeThreadNotificationEnvelope notification)  notification,required TResult Function( BridgeCurrentRevision revision,  BridgeCurrentProjection projection)  projection,}) {final _that = this;
switch (_that) {
case BridgeCurrentFrame_Reset():
return reset(_that.view);case BridgeCurrentFrame_Notification():
return notification(_that.revision,_that.notification);case BridgeCurrentFrame_Projection():
return projection(_that.revision,_that.projection);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeCurrentView view)?  reset,TResult? Function( BridgeCurrentRevision revision,  BridgeThreadNotificationEnvelope notification)?  notification,TResult? Function( BridgeCurrentRevision revision,  BridgeCurrentProjection projection)?  projection,}) {final _that = this;
switch (_that) {
case BridgeCurrentFrame_Reset() when reset != null:
return reset(_that.view);case BridgeCurrentFrame_Notification() when notification != null:
return notification(_that.revision,_that.notification);case BridgeCurrentFrame_Projection() when projection != null:
return projection(_that.revision,_that.projection);case _:
  return null;

}
}

}

/// @nodoc


class BridgeCurrentFrame_Reset extends BridgeCurrentFrame {
  const BridgeCurrentFrame_Reset({required this.view}): super._();


 final  BridgeCurrentView view;

/// Create a copy of BridgeCurrentFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCurrentFrame_ResetCopyWith<BridgeCurrentFrame_Reset> get copyWith => _$BridgeCurrentFrame_ResetCopyWithImpl<BridgeCurrentFrame_Reset>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentFrame_Reset&&(identical(other.view, view) || other.view == view));
}


@override
int get hashCode {
    return Object.hash(runtimeType,view);
}

@override
String toString() {
    return 'BridgeCurrentFrame.reset(view: $view)';
}


}

/// @nodoc
abstract mixin class $BridgeCurrentFrame_ResetCopyWith<$Res> implements $BridgeCurrentFrameCopyWith<$Res> {
  factory $BridgeCurrentFrame_ResetCopyWith(BridgeCurrentFrame_Reset value, $Res Function(BridgeCurrentFrame_Reset) _then) = _$BridgeCurrentFrame_ResetCopyWithImpl;
@useResult
$Res call({
 BridgeCurrentView view
});




}
/// @nodoc
class _$BridgeCurrentFrame_ResetCopyWithImpl<$Res>
    implements $BridgeCurrentFrame_ResetCopyWith<$Res> {
  _$BridgeCurrentFrame_ResetCopyWithImpl(this._self, this._then);

  final BridgeCurrentFrame_Reset _self;
  final $Res Function(BridgeCurrentFrame_Reset) _then;

/// Create a copy of BridgeCurrentFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? view = null,}) {
  return _then(BridgeCurrentFrame_Reset(
view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as BridgeCurrentView,
  ));
}


}

/// @nodoc


class BridgeCurrentFrame_Notification extends BridgeCurrentFrame {
  const BridgeCurrentFrame_Notification({required this.revision, required this.notification}): super._();


 final  BridgeCurrentRevision revision;
 final  BridgeThreadNotificationEnvelope notification;

/// Create a copy of BridgeCurrentFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCurrentFrame_NotificationCopyWith<BridgeCurrentFrame_Notification> get copyWith => _$BridgeCurrentFrame_NotificationCopyWithImpl<BridgeCurrentFrame_Notification>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentFrame_Notification&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.notification, notification) || other.notification == notification));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,notification);
}

@override
String toString() {
    return 'BridgeCurrentFrame.notification(revision: $revision, notification: $notification)';
}


}

/// @nodoc
abstract mixin class $BridgeCurrentFrame_NotificationCopyWith<$Res> implements $BridgeCurrentFrameCopyWith<$Res> {
  factory $BridgeCurrentFrame_NotificationCopyWith(BridgeCurrentFrame_Notification value, $Res Function(BridgeCurrentFrame_Notification) _then) = _$BridgeCurrentFrame_NotificationCopyWithImpl;
@useResult
$Res call({
 BridgeCurrentRevision revision, BridgeThreadNotificationEnvelope notification
});




}
/// @nodoc
class _$BridgeCurrentFrame_NotificationCopyWithImpl<$Res>
    implements $BridgeCurrentFrame_NotificationCopyWith<$Res> {
  _$BridgeCurrentFrame_NotificationCopyWithImpl(this._self, this._then);

  final BridgeCurrentFrame_Notification _self;
  final $Res Function(BridgeCurrentFrame_Notification) _then;

/// Create a copy of BridgeCurrentFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? notification = null,}) {
  return _then(BridgeCurrentFrame_Notification(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BridgeCurrentRevision,notification: null == notification ? _self.notification : notification // ignore: cast_nullable_to_non_nullable
as BridgeThreadNotificationEnvelope,
  ));
}


}

/// @nodoc


class BridgeCurrentFrame_Projection extends BridgeCurrentFrame {
  const BridgeCurrentFrame_Projection({required this.revision, required this.projection}): super._();


 final  BridgeCurrentRevision revision;
 final  BridgeCurrentProjection projection;

/// Create a copy of BridgeCurrentFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCurrentFrame_ProjectionCopyWith<BridgeCurrentFrame_Projection> get copyWith => _$BridgeCurrentFrame_ProjectionCopyWithImpl<BridgeCurrentFrame_Projection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentFrame_Projection&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.projection, projection) || other.projection == projection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,projection);
}

@override
String toString() {
    return 'BridgeCurrentFrame.projection(revision: $revision, projection: $projection)';
}


}

/// @nodoc
abstract mixin class $BridgeCurrentFrame_ProjectionCopyWith<$Res> implements $BridgeCurrentFrameCopyWith<$Res> {
  factory $BridgeCurrentFrame_ProjectionCopyWith(BridgeCurrentFrame_Projection value, $Res Function(BridgeCurrentFrame_Projection) _then) = _$BridgeCurrentFrame_ProjectionCopyWithImpl;
@useResult
$Res call({
 BridgeCurrentRevision revision, BridgeCurrentProjection projection
});




}
/// @nodoc
class _$BridgeCurrentFrame_ProjectionCopyWithImpl<$Res>
    implements $BridgeCurrentFrame_ProjectionCopyWith<$Res> {
  _$BridgeCurrentFrame_ProjectionCopyWithImpl(this._self, this._then);

  final BridgeCurrentFrame_Projection _self;
  final $Res Function(BridgeCurrentFrame_Projection) _then;

/// Create a copy of BridgeCurrentFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? projection = null,}) {
  return _then(BridgeCurrentFrame_Projection(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BridgeCurrentRevision,projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as BridgeCurrentProjection,
  ));
}


}

/// @nodoc
mixin _$BridgeCurrentPayloadData {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentPayloadData);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeCurrentPayloadData()';
}


}

/// @nodoc
class $BridgeCurrentPayloadDataCopyWith<$Res>  {
$BridgeCurrentPayloadDataCopyWith(BridgeCurrentPayloadData _, $Res Function(BridgeCurrentPayloadData) __);
}


/// Adds pattern-matching-related methods to [BridgeCurrentPayloadData].
extension BridgeCurrentPayloadDataPatterns on BridgeCurrentPayloadData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeCurrentPayloadData_Inline value)?  inline,TResult Function( BridgeCurrentPayloadData_Deferred value)?  deferred_,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeCurrentPayloadData_Inline() when inline != null:
return inline(_that);case BridgeCurrentPayloadData_Deferred() when deferred_ != null:
return deferred_(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeCurrentPayloadData_Inline value)  inline,required TResult Function( BridgeCurrentPayloadData_Deferred value)  deferred_,}){
final _that = this;
switch (_that) {
case BridgeCurrentPayloadData_Inline():
return inline(_that);case BridgeCurrentPayloadData_Deferred():
return deferred_(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeCurrentPayloadData_Inline value)?  inline,TResult? Function( BridgeCurrentPayloadData_Deferred value)?  deferred_,}){
final _that = this;
switch (_that) {
case BridgeCurrentPayloadData_Inline() when inline != null:
return inline(_that);case BridgeCurrentPayloadData_Deferred() when deferred_ != null:
return deferred_(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Uint8List bytes)?  inline,TResult Function( BridgeCurrentContentRef reference,  BigInt byteLength)?  deferred_,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeCurrentPayloadData_Inline() when inline != null:
return inline(_that.bytes);case BridgeCurrentPayloadData_Deferred() when deferred_ != null:
return deferred_(_that.reference,_that.byteLength);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Uint8List bytes)  inline,required TResult Function( BridgeCurrentContentRef reference,  BigInt byteLength)  deferred_,}) {final _that = this;
switch (_that) {
case BridgeCurrentPayloadData_Inline():
return inline(_that.bytes);case BridgeCurrentPayloadData_Deferred():
return deferred_(_that.reference,_that.byteLength);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Uint8List bytes)?  inline,TResult? Function( BridgeCurrentContentRef reference,  BigInt byteLength)?  deferred_,}) {final _that = this;
switch (_that) {
case BridgeCurrentPayloadData_Inline() when inline != null:
return inline(_that.bytes);case BridgeCurrentPayloadData_Deferred() when deferred_ != null:
return deferred_(_that.reference,_that.byteLength);case _:
  return null;

}
}

}

/// @nodoc


class BridgeCurrentPayloadData_Inline extends BridgeCurrentPayloadData {
  const BridgeCurrentPayloadData_Inline({required this.bytes}): super._();


 final  Uint8List bytes;

/// Create a copy of BridgeCurrentPayloadData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCurrentPayloadData_InlineCopyWith<BridgeCurrentPayloadData_Inline> get copyWith => _$BridgeCurrentPayloadData_InlineCopyWithImpl<BridgeCurrentPayloadData_Inline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentPayloadData_Inline&&const DeepCollectionEquality().equals(other.bytes, bytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(bytes));
}

@override
String toString() {
    return 'BridgeCurrentPayloadData.inline(bytes: $bytes)';
}


}

/// @nodoc
abstract mixin class $BridgeCurrentPayloadData_InlineCopyWith<$Res> implements $BridgeCurrentPayloadDataCopyWith<$Res> {
  factory $BridgeCurrentPayloadData_InlineCopyWith(BridgeCurrentPayloadData_Inline value, $Res Function(BridgeCurrentPayloadData_Inline) _then) = _$BridgeCurrentPayloadData_InlineCopyWithImpl;
@useResult
$Res call({
 Uint8List bytes
});




}
/// @nodoc
class _$BridgeCurrentPayloadData_InlineCopyWithImpl<$Res>
    implements $BridgeCurrentPayloadData_InlineCopyWith<$Res> {
  _$BridgeCurrentPayloadData_InlineCopyWithImpl(this._self, this._then);

  final BridgeCurrentPayloadData_Inline _self;
  final $Res Function(BridgeCurrentPayloadData_Inline) _then;

/// Create a copy of BridgeCurrentPayloadData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,}) {
  return _then(BridgeCurrentPayloadData_Inline(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class BridgeCurrentPayloadData_Deferred extends BridgeCurrentPayloadData {
  const BridgeCurrentPayloadData_Deferred({required this.reference, required this.byteLength}): super._();


 final  BridgeCurrentContentRef reference;
 final  BigInt byteLength;

/// Create a copy of BridgeCurrentPayloadData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCurrentPayloadData_DeferredCopyWith<BridgeCurrentPayloadData_Deferred> get copyWith => _$BridgeCurrentPayloadData_DeferredCopyWithImpl<BridgeCurrentPayloadData_Deferred>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentPayloadData_Deferred&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.byteLength, byteLength) || other.byteLength == byteLength));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,byteLength);
}

@override
String toString() {
    return 'BridgeCurrentPayloadData.deferred_(reference: $reference, byteLength: $byteLength)';
}


}

/// @nodoc
abstract mixin class $BridgeCurrentPayloadData_DeferredCopyWith<$Res> implements $BridgeCurrentPayloadDataCopyWith<$Res> {
  factory $BridgeCurrentPayloadData_DeferredCopyWith(BridgeCurrentPayloadData_Deferred value, $Res Function(BridgeCurrentPayloadData_Deferred) _then) = _$BridgeCurrentPayloadData_DeferredCopyWithImpl;
@useResult
$Res call({
 BridgeCurrentContentRef reference, BigInt byteLength
});




}
/// @nodoc
class _$BridgeCurrentPayloadData_DeferredCopyWithImpl<$Res>
    implements $BridgeCurrentPayloadData_DeferredCopyWith<$Res> {
  _$BridgeCurrentPayloadData_DeferredCopyWithImpl(this._self, this._then);

  final BridgeCurrentPayloadData_Deferred _self;
  final $Res Function(BridgeCurrentPayloadData_Deferred) _then;

/// Create a copy of BridgeCurrentPayloadData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? byteLength = null,}) {
  return _then(BridgeCurrentPayloadData_Deferred(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as BridgeCurrentContentRef,byteLength: null == byteLength ? _self.byteLength : byteLength // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc
mixin _$BridgeCurrentStateField {

 String get field; Object get reference;
/// Create a copy of BridgeCurrentStateField
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCurrentStateFieldCopyWith<BridgeCurrentStateField> get copyWith => _$BridgeCurrentStateFieldCopyWithImpl<BridgeCurrentStateField>(this as BridgeCurrentStateField, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeCurrentStateField;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentStateField&&(identical(other.field, _this.field) || other.field == _this.field)&&const DeepCollectionEquality().equals(other.reference, _this.reference));
}


@override
int get hashCode {
  final _this = this as BridgeCurrentStateField;
  return Object.hash(runtimeType,_this.field,const DeepCollectionEquality().hash(_this.reference));
}

@override
String toString() {
  final _this = this as BridgeCurrentStateField;
  return 'BridgeCurrentStateField(field: ${_this.field}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $BridgeCurrentStateFieldCopyWith<$Res>  {
  factory $BridgeCurrentStateFieldCopyWith(BridgeCurrentStateField value, $Res Function(BridgeCurrentStateField) _then) = _$BridgeCurrentStateFieldCopyWithImpl;
@useResult
$Res call({
 String field
});




}
/// @nodoc
class _$BridgeCurrentStateFieldCopyWithImpl<$Res>
    implements $BridgeCurrentStateFieldCopyWith<$Res> {
  _$BridgeCurrentStateFieldCopyWithImpl(this._self, this._then);

  final BridgeCurrentStateField _self;
  final $Res Function(BridgeCurrentStateField) _then;

/// Create a copy of BridgeCurrentStateField
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field = null,}) {
  return _then(_self.copyWith(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeCurrentStateField].
extension BridgeCurrentStateFieldPatterns on BridgeCurrentStateField {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeCurrentStateField_Body value)?  body,TResult Function( BridgeCurrentStateField_Collection value)?  collection,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeCurrentStateField_Body() when body != null:
return body(_that);case BridgeCurrentStateField_Collection() when collection != null:
return collection(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeCurrentStateField_Body value)  body,required TResult Function( BridgeCurrentStateField_Collection value)  collection,}){
final _that = this;
switch (_that) {
case BridgeCurrentStateField_Body():
return body(_that);case BridgeCurrentStateField_Collection():
return collection(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeCurrentStateField_Body value)?  body,TResult? Function( BridgeCurrentStateField_Collection value)?  collection,}){
final _that = this;
switch (_that) {
case BridgeCurrentStateField_Body() when body != null:
return body(_that);case BridgeCurrentStateField_Collection() when collection != null:
return collection(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field,  BridgeCurrentContentRef reference,  BigInt byteLength)?  body,TResult Function( String field,  BridgeCurrentCollectionRef reference,  BigInt count)?  collection,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeCurrentStateField_Body() when body != null:
return body(_that.field,_that.reference,_that.byteLength);case BridgeCurrentStateField_Collection() when collection != null:
return collection(_that.field,_that.reference,_that.count);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field,  BridgeCurrentContentRef reference,  BigInt byteLength)  body,required TResult Function( String field,  BridgeCurrentCollectionRef reference,  BigInt count)  collection,}) {final _that = this;
switch (_that) {
case BridgeCurrentStateField_Body():
return body(_that.field,_that.reference,_that.byteLength);case BridgeCurrentStateField_Collection():
return collection(_that.field,_that.reference,_that.count);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field,  BridgeCurrentContentRef reference,  BigInt byteLength)?  body,TResult? Function( String field,  BridgeCurrentCollectionRef reference,  BigInt count)?  collection,}) {final _that = this;
switch (_that) {
case BridgeCurrentStateField_Body() when body != null:
return body(_that.field,_that.reference,_that.byteLength);case BridgeCurrentStateField_Collection() when collection != null:
return collection(_that.field,_that.reference,_that.count);case _:
  return null;

}
}

}

/// @nodoc


class BridgeCurrentStateField_Body extends BridgeCurrentStateField {
  const BridgeCurrentStateField_Body({required this.field, required this.reference, required this.byteLength}): super._();


@override final  String field;
@override final  BridgeCurrentContentRef reference;
 final  BigInt byteLength;

/// Create a copy of BridgeCurrentStateField
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCurrentStateField_BodyCopyWith<BridgeCurrentStateField_Body> get copyWith => _$BridgeCurrentStateField_BodyCopyWithImpl<BridgeCurrentStateField_Body>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentStateField_Body&&(identical(other.field, field) || other.field == field)&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.byteLength, byteLength) || other.byteLength == byteLength));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field,reference,byteLength);
}

@override
String toString() {
    return 'BridgeCurrentStateField.body(field: $field, reference: $reference, byteLength: $byteLength)';
}


}

/// @nodoc
abstract mixin class $BridgeCurrentStateField_BodyCopyWith<$Res> implements $BridgeCurrentStateFieldCopyWith<$Res> {
  factory $BridgeCurrentStateField_BodyCopyWith(BridgeCurrentStateField_Body value, $Res Function(BridgeCurrentStateField_Body) _then) = _$BridgeCurrentStateField_BodyCopyWithImpl;
@override @useResult
$Res call({
 String field, BridgeCurrentContentRef reference, BigInt byteLength
});




}
/// @nodoc
class _$BridgeCurrentStateField_BodyCopyWithImpl<$Res>
    implements $BridgeCurrentStateField_BodyCopyWith<$Res> {
  _$BridgeCurrentStateField_BodyCopyWithImpl(this._self, this._then);

  final BridgeCurrentStateField_Body _self;
  final $Res Function(BridgeCurrentStateField_Body) _then;

/// Create a copy of BridgeCurrentStateField
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field = null,Object? reference = null,Object? byteLength = null,}) {
  return _then(BridgeCurrentStateField_Body(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as BridgeCurrentContentRef,byteLength: null == byteLength ? _self.byteLength : byteLength // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeCurrentStateField_Collection extends BridgeCurrentStateField {
  const BridgeCurrentStateField_Collection({required this.field, required this.reference, required this.count}): super._();


@override final  String field;
@override final  BridgeCurrentCollectionRef reference;
 final  BigInt count;

/// Create a copy of BridgeCurrentStateField
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCurrentStateField_CollectionCopyWith<BridgeCurrentStateField_Collection> get copyWith => _$BridgeCurrentStateField_CollectionCopyWithImpl<BridgeCurrentStateField_Collection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCurrentStateField_Collection&&(identical(other.field, field) || other.field == field)&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field,reference,count);
}

@override
String toString() {
    return 'BridgeCurrentStateField.collection(field: $field, reference: $reference, count: $count)';
}


}

/// @nodoc
abstract mixin class $BridgeCurrentStateField_CollectionCopyWith<$Res> implements $BridgeCurrentStateFieldCopyWith<$Res> {
  factory $BridgeCurrentStateField_CollectionCopyWith(BridgeCurrentStateField_Collection value, $Res Function(BridgeCurrentStateField_Collection) _then) = _$BridgeCurrentStateField_CollectionCopyWithImpl;
@override @useResult
$Res call({
 String field, BridgeCurrentCollectionRef reference, BigInt count
});




}
/// @nodoc
class _$BridgeCurrentStateField_CollectionCopyWithImpl<$Res>
    implements $BridgeCurrentStateField_CollectionCopyWith<$Res> {
  _$BridgeCurrentStateField_CollectionCopyWithImpl(this._self, this._then);

  final BridgeCurrentStateField_Collection _self;
  final $Res Function(BridgeCurrentStateField_Collection) _then;

/// Create a copy of BridgeCurrentStateField
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field = null,Object? reference = null,Object? count = null,}) {
  return _then(BridgeCurrentStateField_Collection(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as BridgeCurrentCollectionRef,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc
mixin _$BridgeHistoryBodyRole {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryBodyRole()';
}


}

/// @nodoc
class $BridgeHistoryBodyRoleCopyWith<$Res>  {
$BridgeHistoryBodyRoleCopyWith(BridgeHistoryBodyRole _, $Res Function(BridgeHistoryBodyRole) __);
}


/// Adds pattern-matching-related methods to [BridgeHistoryBodyRole].
extension BridgeHistoryBodyRolePatterns on BridgeHistoryBodyRole {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryBodyRole_CanonicalPayload value)?  canonicalPayload,TResult Function( BridgeHistoryBodyRole_CanonicalMetadata value)?  canonicalMetadata,TResult Function( BridgeHistoryBodyRole_Body value)?  body,TResult Function( BridgeHistoryBodyRole_ReasoningSummary value)?  reasoningSummary,TResult Function( BridgeHistoryBodyRole_ToolArguments value)?  toolArguments,TResult Function( BridgeHistoryBodyRole_ToolOutput value)?  toolOutput,TResult Function( BridgeHistoryBodyRole_Attachment value)?  attachment,TResult Function( BridgeHistoryBodyRole_WaitPresentation value)?  waitPresentation,TResult Function( BridgeHistoryBodyRole_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryBodyRole_CanonicalPayload() when canonicalPayload != null:
return canonicalPayload(_that);case BridgeHistoryBodyRole_CanonicalMetadata() when canonicalMetadata != null:
return canonicalMetadata(_that);case BridgeHistoryBodyRole_Body() when body != null:
return body(_that);case BridgeHistoryBodyRole_ReasoningSummary() when reasoningSummary != null:
return reasoningSummary(_that);case BridgeHistoryBodyRole_ToolArguments() when toolArguments != null:
return toolArguments(_that);case BridgeHistoryBodyRole_ToolOutput() when toolOutput != null:
return toolOutput(_that);case BridgeHistoryBodyRole_Attachment() when attachment != null:
return attachment(_that);case BridgeHistoryBodyRole_WaitPresentation() when waitPresentation != null:
return waitPresentation(_that);case BridgeHistoryBodyRole_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryBodyRole_CanonicalPayload value)  canonicalPayload,required TResult Function( BridgeHistoryBodyRole_CanonicalMetadata value)  canonicalMetadata,required TResult Function( BridgeHistoryBodyRole_Body value)  body,required TResult Function( BridgeHistoryBodyRole_ReasoningSummary value)  reasoningSummary,required TResult Function( BridgeHistoryBodyRole_ToolArguments value)  toolArguments,required TResult Function( BridgeHistoryBodyRole_ToolOutput value)  toolOutput,required TResult Function( BridgeHistoryBodyRole_Attachment value)  attachment,required TResult Function( BridgeHistoryBodyRole_WaitPresentation value)  waitPresentation,required TResult Function( BridgeHistoryBodyRole_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeHistoryBodyRole_CanonicalPayload():
return canonicalPayload(_that);case BridgeHistoryBodyRole_CanonicalMetadata():
return canonicalMetadata(_that);case BridgeHistoryBodyRole_Body():
return body(_that);case BridgeHistoryBodyRole_ReasoningSummary():
return reasoningSummary(_that);case BridgeHistoryBodyRole_ToolArguments():
return toolArguments(_that);case BridgeHistoryBodyRole_ToolOutput():
return toolOutput(_that);case BridgeHistoryBodyRole_Attachment():
return attachment(_that);case BridgeHistoryBodyRole_WaitPresentation():
return waitPresentation(_that);case BridgeHistoryBodyRole_Other():
return other(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryBodyRole_CanonicalPayload value)?  canonicalPayload,TResult? Function( BridgeHistoryBodyRole_CanonicalMetadata value)?  canonicalMetadata,TResult? Function( BridgeHistoryBodyRole_Body value)?  body,TResult? Function( BridgeHistoryBodyRole_ReasoningSummary value)?  reasoningSummary,TResult? Function( BridgeHistoryBodyRole_ToolArguments value)?  toolArguments,TResult? Function( BridgeHistoryBodyRole_ToolOutput value)?  toolOutput,TResult? Function( BridgeHistoryBodyRole_Attachment value)?  attachment,TResult? Function( BridgeHistoryBodyRole_WaitPresentation value)?  waitPresentation,TResult? Function( BridgeHistoryBodyRole_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeHistoryBodyRole_CanonicalPayload() when canonicalPayload != null:
return canonicalPayload(_that);case BridgeHistoryBodyRole_CanonicalMetadata() when canonicalMetadata != null:
return canonicalMetadata(_that);case BridgeHistoryBodyRole_Body() when body != null:
return body(_that);case BridgeHistoryBodyRole_ReasoningSummary() when reasoningSummary != null:
return reasoningSummary(_that);case BridgeHistoryBodyRole_ToolArguments() when toolArguments != null:
return toolArguments(_that);case BridgeHistoryBodyRole_ToolOutput() when toolOutput != null:
return toolOutput(_that);case BridgeHistoryBodyRole_Attachment() when attachment != null:
return attachment(_that);case BridgeHistoryBodyRole_WaitPresentation() when waitPresentation != null:
return waitPresentation(_that);case BridgeHistoryBodyRole_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  canonicalPayload,TResult Function()?  canonicalMetadata,TResult Function()?  body,TResult Function()?  reasoningSummary,TResult Function()?  toolArguments,TResult Function()?  toolOutput,TResult Function()?  attachment,TResult Function()?  waitPresentation,TResult Function( String name)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryBodyRole_CanonicalPayload() when canonicalPayload != null:
return canonicalPayload();case BridgeHistoryBodyRole_CanonicalMetadata() when canonicalMetadata != null:
return canonicalMetadata();case BridgeHistoryBodyRole_Body() when body != null:
return body();case BridgeHistoryBodyRole_ReasoningSummary() when reasoningSummary != null:
return reasoningSummary();case BridgeHistoryBodyRole_ToolArguments() when toolArguments != null:
return toolArguments();case BridgeHistoryBodyRole_ToolOutput() when toolOutput != null:
return toolOutput();case BridgeHistoryBodyRole_Attachment() when attachment != null:
return attachment();case BridgeHistoryBodyRole_WaitPresentation() when waitPresentation != null:
return waitPresentation();case BridgeHistoryBodyRole_Other() when other != null:
return other(_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  canonicalPayload,required TResult Function()  canonicalMetadata,required TResult Function()  body,required TResult Function()  reasoningSummary,required TResult Function()  toolArguments,required TResult Function()  toolOutput,required TResult Function()  attachment,required TResult Function()  waitPresentation,required TResult Function( String name)  other,}) {final _that = this;
switch (_that) {
case BridgeHistoryBodyRole_CanonicalPayload():
return canonicalPayload();case BridgeHistoryBodyRole_CanonicalMetadata():
return canonicalMetadata();case BridgeHistoryBodyRole_Body():
return body();case BridgeHistoryBodyRole_ReasoningSummary():
return reasoningSummary();case BridgeHistoryBodyRole_ToolArguments():
return toolArguments();case BridgeHistoryBodyRole_ToolOutput():
return toolOutput();case BridgeHistoryBodyRole_Attachment():
return attachment();case BridgeHistoryBodyRole_WaitPresentation():
return waitPresentation();case BridgeHistoryBodyRole_Other():
return other(_that.name);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  canonicalPayload,TResult? Function()?  canonicalMetadata,TResult? Function()?  body,TResult? Function()?  reasoningSummary,TResult? Function()?  toolArguments,TResult? Function()?  toolOutput,TResult? Function()?  attachment,TResult? Function()?  waitPresentation,TResult? Function( String name)?  other,}) {final _that = this;
switch (_that) {
case BridgeHistoryBodyRole_CanonicalPayload() when canonicalPayload != null:
return canonicalPayload();case BridgeHistoryBodyRole_CanonicalMetadata() when canonicalMetadata != null:
return canonicalMetadata();case BridgeHistoryBodyRole_Body() when body != null:
return body();case BridgeHistoryBodyRole_ReasoningSummary() when reasoningSummary != null:
return reasoningSummary();case BridgeHistoryBodyRole_ToolArguments() when toolArguments != null:
return toolArguments();case BridgeHistoryBodyRole_ToolOutput() when toolOutput != null:
return toolOutput();case BridgeHistoryBodyRole_Attachment() when attachment != null:
return attachment();case BridgeHistoryBodyRole_WaitPresentation() when waitPresentation != null:
return waitPresentation();case BridgeHistoryBodyRole_Other() when other != null:
return other(_that.name);case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistoryBodyRole_CanonicalPayload extends BridgeHistoryBodyRole {
  const BridgeHistoryBodyRole_CanonicalPayload(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole_CanonicalPayload);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryBodyRole.canonicalPayload()';
}


}




/// @nodoc


class BridgeHistoryBodyRole_CanonicalMetadata extends BridgeHistoryBodyRole {
  const BridgeHistoryBodyRole_CanonicalMetadata(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole_CanonicalMetadata);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryBodyRole.canonicalMetadata()';
}


}




/// @nodoc


class BridgeHistoryBodyRole_Body extends BridgeHistoryBodyRole {
  const BridgeHistoryBodyRole_Body(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole_Body);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryBodyRole.body()';
}


}




/// @nodoc


class BridgeHistoryBodyRole_ReasoningSummary extends BridgeHistoryBodyRole {
  const BridgeHistoryBodyRole_ReasoningSummary(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole_ReasoningSummary);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryBodyRole.reasoningSummary()';
}


}




/// @nodoc


class BridgeHistoryBodyRole_ToolArguments extends BridgeHistoryBodyRole {
  const BridgeHistoryBodyRole_ToolArguments(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole_ToolArguments);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryBodyRole.toolArguments()';
}


}




/// @nodoc


class BridgeHistoryBodyRole_ToolOutput extends BridgeHistoryBodyRole {
  const BridgeHistoryBodyRole_ToolOutput(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole_ToolOutput);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryBodyRole.toolOutput()';
}


}




/// @nodoc


class BridgeHistoryBodyRole_Attachment extends BridgeHistoryBodyRole {
  const BridgeHistoryBodyRole_Attachment(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole_Attachment);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryBodyRole.attachment()';
}


}




/// @nodoc


class BridgeHistoryBodyRole_WaitPresentation extends BridgeHistoryBodyRole {
  const BridgeHistoryBodyRole_WaitPresentation(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole_WaitPresentation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryBodyRole.waitPresentation()';
}


}




/// @nodoc


class BridgeHistoryBodyRole_Other extends BridgeHistoryBodyRole {
  const BridgeHistoryBodyRole_Other({required this.name}): super._();


 final  String name;

/// Create a copy of BridgeHistoryBodyRole
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryBodyRole_OtherCopyWith<BridgeHistoryBodyRole_Other> get copyWith => _$BridgeHistoryBodyRole_OtherCopyWithImpl<BridgeHistoryBodyRole_Other>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBodyRole_Other&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'BridgeHistoryBodyRole.other(name: $name)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryBodyRole_OtherCopyWith<$Res> implements $BridgeHistoryBodyRoleCopyWith<$Res> {
  factory $BridgeHistoryBodyRole_OtherCopyWith(BridgeHistoryBodyRole_Other value, $Res Function(BridgeHistoryBodyRole_Other) _then) = _$BridgeHistoryBodyRole_OtherCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$BridgeHistoryBodyRole_OtherCopyWithImpl<$Res>
    implements $BridgeHistoryBodyRole_OtherCopyWith<$Res> {
  _$BridgeHistoryBodyRole_OtherCopyWithImpl(this._self, this._then);

  final BridgeHistoryBodyRole_Other _self;
  final $Res Function(BridgeHistoryBodyRole_Other) _then;

/// Create a copy of BridgeHistoryBodyRole
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(BridgeHistoryBodyRole_Other(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeHistoryBusinessRowHead {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as BridgeHistoryBusinessRowHead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBusinessRowHead&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as BridgeHistoryBusinessRowHead;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as BridgeHistoryBusinessRowHead;
  return 'BridgeHistoryBusinessRowHead(field0: ${_this.field0})';
}


}

/// @nodoc
class $BridgeHistoryBusinessRowHeadCopyWith<$Res>  {
$BridgeHistoryBusinessRowHeadCopyWith(BridgeHistoryBusinessRowHead _, $Res Function(BridgeHistoryBusinessRowHead) __);
}


/// Adds pattern-matching-related methods to [BridgeHistoryBusinessRowHead].
extension BridgeHistoryBusinessRowHeadPatterns on BridgeHistoryBusinessRowHead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryBusinessRowHead_Turn value)?  turn,TResult Function( BridgeHistoryBusinessRowHead_Source value)?  source,TResult Function( BridgeHistoryBusinessRowHead_Cost value)?  cost,TResult Function( BridgeHistoryBusinessRowHead_Accounting value)?  accounting,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryBusinessRowHead_Turn() when turn != null:
return turn(_that);case BridgeHistoryBusinessRowHead_Source() when source != null:
return source(_that);case BridgeHistoryBusinessRowHead_Cost() when cost != null:
return cost(_that);case BridgeHistoryBusinessRowHead_Accounting() when accounting != null:
return accounting(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryBusinessRowHead_Turn value)  turn,required TResult Function( BridgeHistoryBusinessRowHead_Source value)  source,required TResult Function( BridgeHistoryBusinessRowHead_Cost value)  cost,required TResult Function( BridgeHistoryBusinessRowHead_Accounting value)  accounting,}){
final _that = this;
switch (_that) {
case BridgeHistoryBusinessRowHead_Turn():
return turn(_that);case BridgeHistoryBusinessRowHead_Source():
return source(_that);case BridgeHistoryBusinessRowHead_Cost():
return cost(_that);case BridgeHistoryBusinessRowHead_Accounting():
return accounting(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryBusinessRowHead_Turn value)?  turn,TResult? Function( BridgeHistoryBusinessRowHead_Source value)?  source,TResult? Function( BridgeHistoryBusinessRowHead_Cost value)?  cost,TResult? Function( BridgeHistoryBusinessRowHead_Accounting value)?  accounting,}){
final _that = this;
switch (_that) {
case BridgeHistoryBusinessRowHead_Turn() when turn != null:
return turn(_that);case BridgeHistoryBusinessRowHead_Source() when source != null:
return source(_that);case BridgeHistoryBusinessRowHead_Cost() when cost != null:
return cost(_that);case BridgeHistoryBusinessRowHead_Accounting() when accounting != null:
return accounting(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeHistoryTurnHead field0)?  turn,TResult Function( BridgeHistorySourceHead field0)?  source,TResult Function( BridgeHistoryCostHead field0)?  cost,TResult Function( BridgeHistoryAccountingHead field0)?  accounting,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryBusinessRowHead_Turn() when turn != null:
return turn(_that.field0);case BridgeHistoryBusinessRowHead_Source() when source != null:
return source(_that.field0);case BridgeHistoryBusinessRowHead_Cost() when cost != null:
return cost(_that.field0);case BridgeHistoryBusinessRowHead_Accounting() when accounting != null:
return accounting(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeHistoryTurnHead field0)  turn,required TResult Function( BridgeHistorySourceHead field0)  source,required TResult Function( BridgeHistoryCostHead field0)  cost,required TResult Function( BridgeHistoryAccountingHead field0)  accounting,}) {final _that = this;
switch (_that) {
case BridgeHistoryBusinessRowHead_Turn():
return turn(_that.field0);case BridgeHistoryBusinessRowHead_Source():
return source(_that.field0);case BridgeHistoryBusinessRowHead_Cost():
return cost(_that.field0);case BridgeHistoryBusinessRowHead_Accounting():
return accounting(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryTurnHead field0)?  turn,TResult? Function( BridgeHistorySourceHead field0)?  source,TResult? Function( BridgeHistoryCostHead field0)?  cost,TResult? Function( BridgeHistoryAccountingHead field0)?  accounting,}) {final _that = this;
switch (_that) {
case BridgeHistoryBusinessRowHead_Turn() when turn != null:
return turn(_that.field0);case BridgeHistoryBusinessRowHead_Source() when source != null:
return source(_that.field0);case BridgeHistoryBusinessRowHead_Cost() when cost != null:
return cost(_that.field0);case BridgeHistoryBusinessRowHead_Accounting() when accounting != null:
return accounting(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistoryBusinessRowHead_Turn extends BridgeHistoryBusinessRowHead {
  const BridgeHistoryBusinessRowHead_Turn(this.field0): super._();


@override final  BridgeHistoryTurnHead field0;

/// Create a copy of BridgeHistoryBusinessRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryBusinessRowHead_TurnCopyWith<BridgeHistoryBusinessRowHead_Turn> get copyWith => _$BridgeHistoryBusinessRowHead_TurnCopyWithImpl<BridgeHistoryBusinessRowHead_Turn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBusinessRowHead_Turn&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryBusinessRowHead.turn(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryBusinessRowHead_TurnCopyWith<$Res> implements $BridgeHistoryBusinessRowHeadCopyWith<$Res> {
  factory $BridgeHistoryBusinessRowHead_TurnCopyWith(BridgeHistoryBusinessRowHead_Turn value, $Res Function(BridgeHistoryBusinessRowHead_Turn) _then) = _$BridgeHistoryBusinessRowHead_TurnCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryTurnHead field0
});




}
/// @nodoc
class _$BridgeHistoryBusinessRowHead_TurnCopyWithImpl<$Res>
    implements $BridgeHistoryBusinessRowHead_TurnCopyWith<$Res> {
  _$BridgeHistoryBusinessRowHead_TurnCopyWithImpl(this._self, this._then);

  final BridgeHistoryBusinessRowHead_Turn _self;
  final $Res Function(BridgeHistoryBusinessRowHead_Turn) _then;

/// Create a copy of BridgeHistoryBusinessRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryBusinessRowHead_Turn(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryTurnHead,
  ));
}


}

/// @nodoc


class BridgeHistoryBusinessRowHead_Source extends BridgeHistoryBusinessRowHead {
  const BridgeHistoryBusinessRowHead_Source(this.field0): super._();


@override final  BridgeHistorySourceHead field0;

/// Create a copy of BridgeHistoryBusinessRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryBusinessRowHead_SourceCopyWith<BridgeHistoryBusinessRowHead_Source> get copyWith => _$BridgeHistoryBusinessRowHead_SourceCopyWithImpl<BridgeHistoryBusinessRowHead_Source>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBusinessRowHead_Source&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryBusinessRowHead.source(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryBusinessRowHead_SourceCopyWith<$Res> implements $BridgeHistoryBusinessRowHeadCopyWith<$Res> {
  factory $BridgeHistoryBusinessRowHead_SourceCopyWith(BridgeHistoryBusinessRowHead_Source value, $Res Function(BridgeHistoryBusinessRowHead_Source) _then) = _$BridgeHistoryBusinessRowHead_SourceCopyWithImpl;
@useResult
$Res call({
 BridgeHistorySourceHead field0
});




}
/// @nodoc
class _$BridgeHistoryBusinessRowHead_SourceCopyWithImpl<$Res>
    implements $BridgeHistoryBusinessRowHead_SourceCopyWith<$Res> {
  _$BridgeHistoryBusinessRowHead_SourceCopyWithImpl(this._self, this._then);

  final BridgeHistoryBusinessRowHead_Source _self;
  final $Res Function(BridgeHistoryBusinessRowHead_Source) _then;

/// Create a copy of BridgeHistoryBusinessRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryBusinessRowHead_Source(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistorySourceHead,
  ));
}


}

/// @nodoc


class BridgeHistoryBusinessRowHead_Cost extends BridgeHistoryBusinessRowHead {
  const BridgeHistoryBusinessRowHead_Cost(this.field0): super._();


@override final  BridgeHistoryCostHead field0;

/// Create a copy of BridgeHistoryBusinessRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryBusinessRowHead_CostCopyWith<BridgeHistoryBusinessRowHead_Cost> get copyWith => _$BridgeHistoryBusinessRowHead_CostCopyWithImpl<BridgeHistoryBusinessRowHead_Cost>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBusinessRowHead_Cost&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryBusinessRowHead.cost(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryBusinessRowHead_CostCopyWith<$Res> implements $BridgeHistoryBusinessRowHeadCopyWith<$Res> {
  factory $BridgeHistoryBusinessRowHead_CostCopyWith(BridgeHistoryBusinessRowHead_Cost value, $Res Function(BridgeHistoryBusinessRowHead_Cost) _then) = _$BridgeHistoryBusinessRowHead_CostCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryCostHead field0
});




}
/// @nodoc
class _$BridgeHistoryBusinessRowHead_CostCopyWithImpl<$Res>
    implements $BridgeHistoryBusinessRowHead_CostCopyWith<$Res> {
  _$BridgeHistoryBusinessRowHead_CostCopyWithImpl(this._self, this._then);

  final BridgeHistoryBusinessRowHead_Cost _self;
  final $Res Function(BridgeHistoryBusinessRowHead_Cost) _then;

/// Create a copy of BridgeHistoryBusinessRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryBusinessRowHead_Cost(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryCostHead,
  ));
}


}

/// @nodoc


class BridgeHistoryBusinessRowHead_Accounting extends BridgeHistoryBusinessRowHead {
  const BridgeHistoryBusinessRowHead_Accounting(this.field0): super._();


@override final  BridgeHistoryAccountingHead field0;

/// Create a copy of BridgeHistoryBusinessRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryBusinessRowHead_AccountingCopyWith<BridgeHistoryBusinessRowHead_Accounting> get copyWith => _$BridgeHistoryBusinessRowHead_AccountingCopyWithImpl<BridgeHistoryBusinessRowHead_Accounting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryBusinessRowHead_Accounting&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryBusinessRowHead.accounting(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryBusinessRowHead_AccountingCopyWith<$Res> implements $BridgeHistoryBusinessRowHeadCopyWith<$Res> {
  factory $BridgeHistoryBusinessRowHead_AccountingCopyWith(BridgeHistoryBusinessRowHead_Accounting value, $Res Function(BridgeHistoryBusinessRowHead_Accounting) _then) = _$BridgeHistoryBusinessRowHead_AccountingCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryAccountingHead field0
});




}
/// @nodoc
class _$BridgeHistoryBusinessRowHead_AccountingCopyWithImpl<$Res>
    implements $BridgeHistoryBusinessRowHead_AccountingCopyWith<$Res> {
  _$BridgeHistoryBusinessRowHead_AccountingCopyWithImpl(this._self, this._then);

  final BridgeHistoryBusinessRowHead_Accounting _self;
  final $Res Function(BridgeHistoryBusinessRowHead_Accounting) _then;

/// Create a copy of BridgeHistoryBusinessRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryBusinessRowHead_Accounting(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryAccountingHead,
  ));
}


}

/// @nodoc
mixin _$BridgeHistoryEventsQuery {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryEventsQuery()';
}


}

/// @nodoc
class $BridgeHistoryEventsQueryCopyWith<$Res>  {
$BridgeHistoryEventsQueryCopyWith(BridgeHistoryEventsQuery _, $Res Function(BridgeHistoryEventsQuery) __);
}


/// Adds pattern-matching-related methods to [BridgeHistoryEventsQuery].
extension BridgeHistoryEventsQueryPatterns on BridgeHistoryEventsQuery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryEventsQuery_AllEvents value)?  allEvents,TResult Function( BridgeHistoryEventsQuery_Entity value)?  entity,TResult Function( BridgeHistoryEventsQuery_Turn value)?  turn,TResult Function( BridgeHistoryEventsQuery_Source value)?  source,TResult Function( BridgeHistoryEventsQuery_Call value)?  call,TResult Function( BridgeHistoryEventsQuery_Originals value)?  originals,TResult Function( BridgeHistoryEventsQuery_TextOriginals value)?  textOriginals,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents() when allEvents != null:
return allEvents(_that);case BridgeHistoryEventsQuery_Entity() when entity != null:
return entity(_that);case BridgeHistoryEventsQuery_Turn() when turn != null:
return turn(_that);case BridgeHistoryEventsQuery_Source() when source != null:
return source(_that);case BridgeHistoryEventsQuery_Call() when call != null:
return call(_that);case BridgeHistoryEventsQuery_Originals() when originals != null:
return originals(_that);case BridgeHistoryEventsQuery_TextOriginals() when textOriginals != null:
return textOriginals(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryEventsQuery_AllEvents value)  allEvents,required TResult Function( BridgeHistoryEventsQuery_Entity value)  entity,required TResult Function( BridgeHistoryEventsQuery_Turn value)  turn,required TResult Function( BridgeHistoryEventsQuery_Source value)  source,required TResult Function( BridgeHistoryEventsQuery_Call value)  call,required TResult Function( BridgeHistoryEventsQuery_Originals value)  originals,required TResult Function( BridgeHistoryEventsQuery_TextOriginals value)  textOriginals,}){
final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents():
return allEvents(_that);case BridgeHistoryEventsQuery_Entity():
return entity(_that);case BridgeHistoryEventsQuery_Turn():
return turn(_that);case BridgeHistoryEventsQuery_Source():
return source(_that);case BridgeHistoryEventsQuery_Call():
return call(_that);case BridgeHistoryEventsQuery_Originals():
return originals(_that);case BridgeHistoryEventsQuery_TextOriginals():
return textOriginals(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryEventsQuery_AllEvents value)?  allEvents,TResult? Function( BridgeHistoryEventsQuery_Entity value)?  entity,TResult? Function( BridgeHistoryEventsQuery_Turn value)?  turn,TResult? Function( BridgeHistoryEventsQuery_Source value)?  source,TResult? Function( BridgeHistoryEventsQuery_Call value)?  call,TResult? Function( BridgeHistoryEventsQuery_Originals value)?  originals,TResult? Function( BridgeHistoryEventsQuery_TextOriginals value)?  textOriginals,}){
final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents() when allEvents != null:
return allEvents(_that);case BridgeHistoryEventsQuery_Entity() when entity != null:
return entity(_that);case BridgeHistoryEventsQuery_Turn() when turn != null:
return turn(_that);case BridgeHistoryEventsQuery_Source() when source != null:
return source(_that);case BridgeHistoryEventsQuery_Call() when call != null:
return call(_that);case BridgeHistoryEventsQuery_Originals() when originals != null:
return originals(_that);case BridgeHistoryEventsQuery_TextOriginals() when textOriginals != null:
return textOriginals(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  allEvents,TResult Function( String entityId)?  entity,TResult Function( String turnId)?  turn,TResult Function( BridgeChatSourceId source)?  source,TResult Function( String callId)?  call,TResult Function( String queryClass,  String? parentId)?  originals,TResult Function()?  textOriginals,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents() when allEvents != null:
return allEvents();case BridgeHistoryEventsQuery_Entity() when entity != null:
return entity(_that.entityId);case BridgeHistoryEventsQuery_Turn() when turn != null:
return turn(_that.turnId);case BridgeHistoryEventsQuery_Source() when source != null:
return source(_that.source);case BridgeHistoryEventsQuery_Call() when call != null:
return call(_that.callId);case BridgeHistoryEventsQuery_Originals() when originals != null:
return originals(_that.queryClass,_that.parentId);case BridgeHistoryEventsQuery_TextOriginals() when textOriginals != null:
return textOriginals();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  allEvents,required TResult Function( String entityId)  entity,required TResult Function( String turnId)  turn,required TResult Function( BridgeChatSourceId source)  source,required TResult Function( String callId)  call,required TResult Function( String queryClass,  String? parentId)  originals,required TResult Function()  textOriginals,}) {final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents():
return allEvents();case BridgeHistoryEventsQuery_Entity():
return entity(_that.entityId);case BridgeHistoryEventsQuery_Turn():
return turn(_that.turnId);case BridgeHistoryEventsQuery_Source():
return source(_that.source);case BridgeHistoryEventsQuery_Call():
return call(_that.callId);case BridgeHistoryEventsQuery_Originals():
return originals(_that.queryClass,_that.parentId);case BridgeHistoryEventsQuery_TextOriginals():
return textOriginals();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  allEvents,TResult? Function( String entityId)?  entity,TResult? Function( String turnId)?  turn,TResult? Function( BridgeChatSourceId source)?  source,TResult? Function( String callId)?  call,TResult? Function( String queryClass,  String? parentId)?  originals,TResult? Function()?  textOriginals,}) {final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents() when allEvents != null:
return allEvents();case BridgeHistoryEventsQuery_Entity() when entity != null:
return entity(_that.entityId);case BridgeHistoryEventsQuery_Turn() when turn != null:
return turn(_that.turnId);case BridgeHistoryEventsQuery_Source() when source != null:
return source(_that.source);case BridgeHistoryEventsQuery_Call() when call != null:
return call(_that.callId);case BridgeHistoryEventsQuery_Originals() when originals != null:
return originals(_that.queryClass,_that.parentId);case BridgeHistoryEventsQuery_TextOriginals() when textOriginals != null:
return textOriginals();case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistoryEventsQuery_AllEvents extends BridgeHistoryEventsQuery {
  const BridgeHistoryEventsQuery_AllEvents(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery_AllEvents);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryEventsQuery.allEvents()';
}


}




/// @nodoc


class BridgeHistoryEventsQuery_Entity extends BridgeHistoryEventsQuery {
  const BridgeHistoryEventsQuery_Entity({required this.entityId}): super._();


 final  String entityId;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryEventsQuery_EntityCopyWith<BridgeHistoryEventsQuery_Entity> get copyWith => _$BridgeHistoryEventsQuery_EntityCopyWithImpl<BridgeHistoryEventsQuery_Entity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery_Entity&&(identical(other.entityId, entityId) || other.entityId == entityId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entityId);
}

@override
String toString() {
    return 'BridgeHistoryEventsQuery.entity(entityId: $entityId)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryEventsQuery_EntityCopyWith<$Res> implements $BridgeHistoryEventsQueryCopyWith<$Res> {
  factory $BridgeHistoryEventsQuery_EntityCopyWith(BridgeHistoryEventsQuery_Entity value, $Res Function(BridgeHistoryEventsQuery_Entity) _then) = _$BridgeHistoryEventsQuery_EntityCopyWithImpl;
@useResult
$Res call({
 String entityId
});




}
/// @nodoc
class _$BridgeHistoryEventsQuery_EntityCopyWithImpl<$Res>
    implements $BridgeHistoryEventsQuery_EntityCopyWith<$Res> {
  _$BridgeHistoryEventsQuery_EntityCopyWithImpl(this._self, this._then);

  final BridgeHistoryEventsQuery_Entity _self;
  final $Res Function(BridgeHistoryEventsQuery_Entity) _then;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entityId = null,}) {
  return _then(BridgeHistoryEventsQuery_Entity(
entityId: null == entityId ? _self.entityId : entityId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeHistoryEventsQuery_Turn extends BridgeHistoryEventsQuery {
  const BridgeHistoryEventsQuery_Turn({required this.turnId}): super._();


 final  String turnId;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryEventsQuery_TurnCopyWith<BridgeHistoryEventsQuery_Turn> get copyWith => _$BridgeHistoryEventsQuery_TurnCopyWithImpl<BridgeHistoryEventsQuery_Turn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery_Turn&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}

@override
String toString() {
    return 'BridgeHistoryEventsQuery.turn(turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryEventsQuery_TurnCopyWith<$Res> implements $BridgeHistoryEventsQueryCopyWith<$Res> {
  factory $BridgeHistoryEventsQuery_TurnCopyWith(BridgeHistoryEventsQuery_Turn value, $Res Function(BridgeHistoryEventsQuery_Turn) _then) = _$BridgeHistoryEventsQuery_TurnCopyWithImpl;
@useResult
$Res call({
 String turnId
});




}
/// @nodoc
class _$BridgeHistoryEventsQuery_TurnCopyWithImpl<$Res>
    implements $BridgeHistoryEventsQuery_TurnCopyWith<$Res> {
  _$BridgeHistoryEventsQuery_TurnCopyWithImpl(this._self, this._then);

  final BridgeHistoryEventsQuery_Turn _self;
  final $Res Function(BridgeHistoryEventsQuery_Turn) _then;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(BridgeHistoryEventsQuery_Turn(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeHistoryEventsQuery_Source extends BridgeHistoryEventsQuery {
  const BridgeHistoryEventsQuery_Source({required this.source}): super._();


 final  BridgeChatSourceId source;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryEventsQuery_SourceCopyWith<BridgeHistoryEventsQuery_Source> get copyWith => _$BridgeHistoryEventsQuery_SourceCopyWithImpl<BridgeHistoryEventsQuery_Source>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery_Source&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source);
}

@override
String toString() {
    return 'BridgeHistoryEventsQuery.source(source: $source)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryEventsQuery_SourceCopyWith<$Res> implements $BridgeHistoryEventsQueryCopyWith<$Res> {
  factory $BridgeHistoryEventsQuery_SourceCopyWith(BridgeHistoryEventsQuery_Source value, $Res Function(BridgeHistoryEventsQuery_Source) _then) = _$BridgeHistoryEventsQuery_SourceCopyWithImpl;
@useResult
$Res call({
 BridgeChatSourceId source
});


$BridgeChatSourceIdCopyWith<$Res> get source;

}
/// @nodoc
class _$BridgeHistoryEventsQuery_SourceCopyWithImpl<$Res>
    implements $BridgeHistoryEventsQuery_SourceCopyWith<$Res> {
  _$BridgeHistoryEventsQuery_SourceCopyWithImpl(this._self, this._then);

  final BridgeHistoryEventsQuery_Source _self;
  final $Res Function(BridgeHistoryEventsQuery_Source) _then;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? source = null,}) {
  return _then(BridgeHistoryEventsQuery_Source(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as BridgeChatSourceId,
  ));
}

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeChatSourceIdCopyWith<$Res> get source {

  return $BridgeChatSourceIdCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}

/// @nodoc


class BridgeHistoryEventsQuery_Call extends BridgeHistoryEventsQuery {
  const BridgeHistoryEventsQuery_Call({required this.callId}): super._();


 final  String callId;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryEventsQuery_CallCopyWith<BridgeHistoryEventsQuery_Call> get copyWith => _$BridgeHistoryEventsQuery_CallCopyWithImpl<BridgeHistoryEventsQuery_Call>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery_Call&&(identical(other.callId, callId) || other.callId == callId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,callId);
}

@override
String toString() {
    return 'BridgeHistoryEventsQuery.call(callId: $callId)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryEventsQuery_CallCopyWith<$Res> implements $BridgeHistoryEventsQueryCopyWith<$Res> {
  factory $BridgeHistoryEventsQuery_CallCopyWith(BridgeHistoryEventsQuery_Call value, $Res Function(BridgeHistoryEventsQuery_Call) _then) = _$BridgeHistoryEventsQuery_CallCopyWithImpl;
@useResult
$Res call({
 String callId
});




}
/// @nodoc
class _$BridgeHistoryEventsQuery_CallCopyWithImpl<$Res>
    implements $BridgeHistoryEventsQuery_CallCopyWith<$Res> {
  _$BridgeHistoryEventsQuery_CallCopyWithImpl(this._self, this._then);

  final BridgeHistoryEventsQuery_Call _self;
  final $Res Function(BridgeHistoryEventsQuery_Call) _then;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? callId = null,}) {
  return _then(BridgeHistoryEventsQuery_Call(
callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeHistoryEventsQuery_Originals extends BridgeHistoryEventsQuery {
  const BridgeHistoryEventsQuery_Originals({required this.queryClass, this.parentId}): super._();


 final  String queryClass;
 final  String? parentId;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryEventsQuery_OriginalsCopyWith<BridgeHistoryEventsQuery_Originals> get copyWith => _$BridgeHistoryEventsQuery_OriginalsCopyWithImpl<BridgeHistoryEventsQuery_Originals>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery_Originals&&(identical(other.queryClass, queryClass) || other.queryClass == queryClass)&&(identical(other.parentId, parentId) || other.parentId == parentId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,queryClass,parentId);
}

@override
String toString() {
    return 'BridgeHistoryEventsQuery.originals(queryClass: $queryClass, parentId: $parentId)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryEventsQuery_OriginalsCopyWith<$Res> implements $BridgeHistoryEventsQueryCopyWith<$Res> {
  factory $BridgeHistoryEventsQuery_OriginalsCopyWith(BridgeHistoryEventsQuery_Originals value, $Res Function(BridgeHistoryEventsQuery_Originals) _then) = _$BridgeHistoryEventsQuery_OriginalsCopyWithImpl;
@useResult
$Res call({
 String queryClass, String? parentId
});




}
/// @nodoc
class _$BridgeHistoryEventsQuery_OriginalsCopyWithImpl<$Res>
    implements $BridgeHistoryEventsQuery_OriginalsCopyWith<$Res> {
  _$BridgeHistoryEventsQuery_OriginalsCopyWithImpl(this._self, this._then);

  final BridgeHistoryEventsQuery_Originals _self;
  final $Res Function(BridgeHistoryEventsQuery_Originals) _then;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? queryClass = null,Object? parentId = freezed,}) {
  return _then(BridgeHistoryEventsQuery_Originals(
queryClass: null == queryClass ? _self.queryClass : queryClass // ignore: cast_nullable_to_non_nullable
as String,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BridgeHistoryEventsQuery_TextOriginals extends BridgeHistoryEventsQuery {
  const BridgeHistoryEventsQuery_TextOriginals(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery_TextOriginals);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryEventsQuery.textOriginals()';
}


}




/// @nodoc
mixin _$BridgeHistorySourceLifecycle {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistorySourceLifecycle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistorySourceLifecycle()';
}


}

/// @nodoc
class $BridgeHistorySourceLifecycleCopyWith<$Res>  {
$BridgeHistorySourceLifecycleCopyWith(BridgeHistorySourceLifecycle _, $Res Function(BridgeHistorySourceLifecycle) __);
}


/// Adds pattern-matching-related methods to [BridgeHistorySourceLifecycle].
extension BridgeHistorySourceLifecyclePatterns on BridgeHistorySourceLifecycle {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistorySourceLifecycle_Unknown value)?  unknown,TResult Function( BridgeHistorySourceLifecycle_Active value)?  active,TResult Function( BridgeHistorySourceLifecycle_Ended value)?  ended,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistorySourceLifecycle_Unknown() when unknown != null:
return unknown(_that);case BridgeHistorySourceLifecycle_Active() when active != null:
return active(_that);case BridgeHistorySourceLifecycle_Ended() when ended != null:
return ended(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistorySourceLifecycle_Unknown value)  unknown,required TResult Function( BridgeHistorySourceLifecycle_Active value)  active,required TResult Function( BridgeHistorySourceLifecycle_Ended value)  ended,}){
final _that = this;
switch (_that) {
case BridgeHistorySourceLifecycle_Unknown():
return unknown(_that);case BridgeHistorySourceLifecycle_Active():
return active(_that);case BridgeHistorySourceLifecycle_Ended():
return ended(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistorySourceLifecycle_Unknown value)?  unknown,TResult? Function( BridgeHistorySourceLifecycle_Active value)?  active,TResult? Function( BridgeHistorySourceLifecycle_Ended value)?  ended,}){
final _that = this;
switch (_that) {
case BridgeHistorySourceLifecycle_Unknown() when unknown != null:
return unknown(_that);case BridgeHistorySourceLifecycle_Active() when active != null:
return active(_that);case BridgeHistorySourceLifecycle_Ended() when ended != null:
return ended(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unknown,TResult Function()?  active,TResult Function( BridgeChatTerminalOutcome outcome)?  ended,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistorySourceLifecycle_Unknown() when unknown != null:
return unknown();case BridgeHistorySourceLifecycle_Active() when active != null:
return active();case BridgeHistorySourceLifecycle_Ended() when ended != null:
return ended(_that.outcome);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unknown,required TResult Function()  active,required TResult Function( BridgeChatTerminalOutcome outcome)  ended,}) {final _that = this;
switch (_that) {
case BridgeHistorySourceLifecycle_Unknown():
return unknown();case BridgeHistorySourceLifecycle_Active():
return active();case BridgeHistorySourceLifecycle_Ended():
return ended(_that.outcome);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unknown,TResult? Function()?  active,TResult? Function( BridgeChatTerminalOutcome outcome)?  ended,}) {final _that = this;
switch (_that) {
case BridgeHistorySourceLifecycle_Unknown() when unknown != null:
return unknown();case BridgeHistorySourceLifecycle_Active() when active != null:
return active();case BridgeHistorySourceLifecycle_Ended() when ended != null:
return ended(_that.outcome);case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistorySourceLifecycle_Unknown extends BridgeHistorySourceLifecycle {
  const BridgeHistorySourceLifecycle_Unknown(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistorySourceLifecycle_Unknown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistorySourceLifecycle.unknown()';
}


}




/// @nodoc


class BridgeHistorySourceLifecycle_Active extends BridgeHistorySourceLifecycle {
  const BridgeHistorySourceLifecycle_Active(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistorySourceLifecycle_Active);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistorySourceLifecycle.active()';
}


}




/// @nodoc


class BridgeHistorySourceLifecycle_Ended extends BridgeHistorySourceLifecycle {
  const BridgeHistorySourceLifecycle_Ended({required this.outcome}): super._();


 final  BridgeChatTerminalOutcome outcome;

/// Create a copy of BridgeHistorySourceLifecycle
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistorySourceLifecycle_EndedCopyWith<BridgeHistorySourceLifecycle_Ended> get copyWith => _$BridgeHistorySourceLifecycle_EndedCopyWithImpl<BridgeHistorySourceLifecycle_Ended>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistorySourceLifecycle_Ended&&(identical(other.outcome, outcome) || other.outcome == outcome));
}


@override
int get hashCode {
    return Object.hash(runtimeType,outcome);
}

@override
String toString() {
    return 'BridgeHistorySourceLifecycle.ended(outcome: $outcome)';
}


}

/// @nodoc
abstract mixin class $BridgeHistorySourceLifecycle_EndedCopyWith<$Res> implements $BridgeHistorySourceLifecycleCopyWith<$Res> {
  factory $BridgeHistorySourceLifecycle_EndedCopyWith(BridgeHistorySourceLifecycle_Ended value, $Res Function(BridgeHistorySourceLifecycle_Ended) _then) = _$BridgeHistorySourceLifecycle_EndedCopyWithImpl;
@useResult
$Res call({
 BridgeChatTerminalOutcome outcome
});




}
/// @nodoc
class _$BridgeHistorySourceLifecycle_EndedCopyWithImpl<$Res>
    implements $BridgeHistorySourceLifecycle_EndedCopyWith<$Res> {
  _$BridgeHistorySourceLifecycle_EndedCopyWithImpl(this._self, this._then);

  final BridgeHistorySourceLifecycle_Ended _self;
  final $Res Function(BridgeHistorySourceLifecycle_Ended) _then;

/// Create a copy of BridgeHistorySourceLifecycle
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? outcome = null,}) {
  return _then(BridgeHistorySourceLifecycle_Ended(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as BridgeChatTerminalOutcome,
  ));
}


}

/// @nodoc
mixin _$BridgeHistoryTimelineItem {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as BridgeHistoryTimelineItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryTimelineItem&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as BridgeHistoryTimelineItem;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as BridgeHistoryTimelineItem;
  return 'BridgeHistoryTimelineItem(field0: ${_this.field0})';
}


}

/// @nodoc
class $BridgeHistoryTimelineItemCopyWith<$Res>  {
$BridgeHistoryTimelineItemCopyWith(BridgeHistoryTimelineItem _, $Res Function(BridgeHistoryTimelineItem) __);
}


/// Adds pattern-matching-related methods to [BridgeHistoryTimelineItem].
extension BridgeHistoryTimelineItemPatterns on BridgeHistoryTimelineItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryTimelineItem_Boundary value)?  boundary,TResult Function( BridgeHistoryTimelineItem_WorkRange value)?  workRange,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryTimelineItem_Boundary() when boundary != null:
return boundary(_that);case BridgeHistoryTimelineItem_WorkRange() when workRange != null:
return workRange(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryTimelineItem_Boundary value)  boundary,required TResult Function( BridgeHistoryTimelineItem_WorkRange value)  workRange,}){
final _that = this;
switch (_that) {
case BridgeHistoryTimelineItem_Boundary():
return boundary(_that);case BridgeHistoryTimelineItem_WorkRange():
return workRange(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryTimelineItem_Boundary value)?  boundary,TResult? Function( BridgeHistoryTimelineItem_WorkRange value)?  workRange,}){
final _that = this;
switch (_that) {
case BridgeHistoryTimelineItem_Boundary() when boundary != null:
return boundary(_that);case BridgeHistoryTimelineItem_WorkRange() when workRange != null:
return workRange(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeHistoryEventRecord field0)?  boundary,TResult Function( BridgeHistoryWorkRange field0)?  workRange,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryTimelineItem_Boundary() when boundary != null:
return boundary(_that.field0);case BridgeHistoryTimelineItem_WorkRange() when workRange != null:
return workRange(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeHistoryEventRecord field0)  boundary,required TResult Function( BridgeHistoryWorkRange field0)  workRange,}) {final _that = this;
switch (_that) {
case BridgeHistoryTimelineItem_Boundary():
return boundary(_that.field0);case BridgeHistoryTimelineItem_WorkRange():
return workRange(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryEventRecord field0)?  boundary,TResult? Function( BridgeHistoryWorkRange field0)?  workRange,}) {final _that = this;
switch (_that) {
case BridgeHistoryTimelineItem_Boundary() when boundary != null:
return boundary(_that.field0);case BridgeHistoryTimelineItem_WorkRange() when workRange != null:
return workRange(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistoryTimelineItem_Boundary extends BridgeHistoryTimelineItem {
  const BridgeHistoryTimelineItem_Boundary(this.field0): super._();


@override final  BridgeHistoryEventRecord field0;

/// Create a copy of BridgeHistoryTimelineItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryTimelineItem_BoundaryCopyWith<BridgeHistoryTimelineItem_Boundary> get copyWith => _$BridgeHistoryTimelineItem_BoundaryCopyWithImpl<BridgeHistoryTimelineItem_Boundary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryTimelineItem_Boundary&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryTimelineItem.boundary(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryTimelineItem_BoundaryCopyWith<$Res> implements $BridgeHistoryTimelineItemCopyWith<$Res> {
  factory $BridgeHistoryTimelineItem_BoundaryCopyWith(BridgeHistoryTimelineItem_Boundary value, $Res Function(BridgeHistoryTimelineItem_Boundary) _then) = _$BridgeHistoryTimelineItem_BoundaryCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryEventRecord field0
});




}
/// @nodoc
class _$BridgeHistoryTimelineItem_BoundaryCopyWithImpl<$Res>
    implements $BridgeHistoryTimelineItem_BoundaryCopyWith<$Res> {
  _$BridgeHistoryTimelineItem_BoundaryCopyWithImpl(this._self, this._then);

  final BridgeHistoryTimelineItem_Boundary _self;
  final $Res Function(BridgeHistoryTimelineItem_Boundary) _then;

/// Create a copy of BridgeHistoryTimelineItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryTimelineItem_Boundary(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryEventRecord,
  ));
}


}

/// @nodoc


class BridgeHistoryTimelineItem_WorkRange extends BridgeHistoryTimelineItem {
  const BridgeHistoryTimelineItem_WorkRange(this.field0): super._();


@override final  BridgeHistoryWorkRange field0;

/// Create a copy of BridgeHistoryTimelineItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryTimelineItem_WorkRangeCopyWith<BridgeHistoryTimelineItem_WorkRange> get copyWith => _$BridgeHistoryTimelineItem_WorkRangeCopyWithImpl<BridgeHistoryTimelineItem_WorkRange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryTimelineItem_WorkRange&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryTimelineItem.workRange(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryTimelineItem_WorkRangeCopyWith<$Res> implements $BridgeHistoryTimelineItemCopyWith<$Res> {
  factory $BridgeHistoryTimelineItem_WorkRangeCopyWith(BridgeHistoryTimelineItem_WorkRange value, $Res Function(BridgeHistoryTimelineItem_WorkRange) _then) = _$BridgeHistoryTimelineItem_WorkRangeCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryWorkRange field0
});




}
/// @nodoc
class _$BridgeHistoryTimelineItem_WorkRangeCopyWithImpl<$Res>
    implements $BridgeHistoryTimelineItem_WorkRangeCopyWith<$Res> {
  _$BridgeHistoryTimelineItem_WorkRangeCopyWithImpl(this._self, this._then);

  final BridgeHistoryTimelineItem_WorkRange _self;
  final $Res Function(BridgeHistoryTimelineItem_WorkRange) _then;

/// Create a copy of BridgeHistoryTimelineItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryTimelineItem_WorkRange(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryWorkRange,
  ));
}


}

// dart format on
