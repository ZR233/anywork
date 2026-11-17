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
mixin _$BridgeHistoryEntityState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEntityState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryEntityState()';
}


}

/// @nodoc
class $BridgeHistoryEntityStateCopyWith<$Res>  {
$BridgeHistoryEntityStateCopyWith(BridgeHistoryEntityState _, $Res Function(BridgeHistoryEntityState) __);
}


/// Adds pattern-matching-related methods to [BridgeHistoryEntityState].
extension BridgeHistoryEntityStatePatterns on BridgeHistoryEntityState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryEntityState_Unknown value)?  unknown,TResult Function( BridgeHistoryEntityState_KnownActive value)?  knownActive,TResult Function( BridgeHistoryEntityState_KnownTerminal value)?  knownTerminal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryEntityState_Unknown() when unknown != null:
return unknown(_that);case BridgeHistoryEntityState_KnownActive() when knownActive != null:
return knownActive(_that);case BridgeHistoryEntityState_KnownTerminal() when knownTerminal != null:
return knownTerminal(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryEntityState_Unknown value)  unknown,required TResult Function( BridgeHistoryEntityState_KnownActive value)  knownActive,required TResult Function( BridgeHistoryEntityState_KnownTerminal value)  knownTerminal,}){
final _that = this;
switch (_that) {
case BridgeHistoryEntityState_Unknown():
return unknown(_that);case BridgeHistoryEntityState_KnownActive():
return knownActive(_that);case BridgeHistoryEntityState_KnownTerminal():
return knownTerminal(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryEntityState_Unknown value)?  unknown,TResult? Function( BridgeHistoryEntityState_KnownActive value)?  knownActive,TResult? Function( BridgeHistoryEntityState_KnownTerminal value)?  knownTerminal,}){
final _that = this;
switch (_that) {
case BridgeHistoryEntityState_Unknown() when unknown != null:
return unknown(_that);case BridgeHistoryEntityState_KnownActive() when knownActive != null:
return knownActive(_that);case BridgeHistoryEntityState_KnownTerminal() when knownTerminal != null:
return knownTerminal(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unknown,TResult Function( BridgeChatActiveStatus status)?  knownActive,TResult Function( BridgeChatTerminalOutcome outcome)?  knownTerminal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryEntityState_Unknown() when unknown != null:
return unknown();case BridgeHistoryEntityState_KnownActive() when knownActive != null:
return knownActive(_that.status);case BridgeHistoryEntityState_KnownTerminal() when knownTerminal != null:
return knownTerminal(_that.outcome);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unknown,required TResult Function( BridgeChatActiveStatus status)  knownActive,required TResult Function( BridgeChatTerminalOutcome outcome)  knownTerminal,}) {final _that = this;
switch (_that) {
case BridgeHistoryEntityState_Unknown():
return unknown();case BridgeHistoryEntityState_KnownActive():
return knownActive(_that.status);case BridgeHistoryEntityState_KnownTerminal():
return knownTerminal(_that.outcome);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unknown,TResult? Function( BridgeChatActiveStatus status)?  knownActive,TResult? Function( BridgeChatTerminalOutcome outcome)?  knownTerminal,}) {final _that = this;
switch (_that) {
case BridgeHistoryEntityState_Unknown() when unknown != null:
return unknown();case BridgeHistoryEntityState_KnownActive() when knownActive != null:
return knownActive(_that.status);case BridgeHistoryEntityState_KnownTerminal() when knownTerminal != null:
return knownTerminal(_that.outcome);case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistoryEntityState_Unknown extends BridgeHistoryEntityState {
  const BridgeHistoryEntityState_Unknown(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEntityState_Unknown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryEntityState.unknown()';
}


}




/// @nodoc


class BridgeHistoryEntityState_KnownActive extends BridgeHistoryEntityState {
  const BridgeHistoryEntityState_KnownActive({required this.status}): super._();


 final  BridgeChatActiveStatus status;

/// Create a copy of BridgeHistoryEntityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryEntityState_KnownActiveCopyWith<BridgeHistoryEntityState_KnownActive> get copyWith => _$BridgeHistoryEntityState_KnownActiveCopyWithImpl<BridgeHistoryEntityState_KnownActive>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEntityState_KnownActive&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status);
}

@override
String toString() {
    return 'BridgeHistoryEntityState.knownActive(status: $status)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryEntityState_KnownActiveCopyWith<$Res> implements $BridgeHistoryEntityStateCopyWith<$Res> {
  factory $BridgeHistoryEntityState_KnownActiveCopyWith(BridgeHistoryEntityState_KnownActive value, $Res Function(BridgeHistoryEntityState_KnownActive) _then) = _$BridgeHistoryEntityState_KnownActiveCopyWithImpl;
@useResult
$Res call({
 BridgeChatActiveStatus status
});




}
/// @nodoc
class _$BridgeHistoryEntityState_KnownActiveCopyWithImpl<$Res>
    implements $BridgeHistoryEntityState_KnownActiveCopyWith<$Res> {
  _$BridgeHistoryEntityState_KnownActiveCopyWithImpl(this._self, this._then);

  final BridgeHistoryEntityState_KnownActive _self;
  final $Res Function(BridgeHistoryEntityState_KnownActive) _then;

/// Create a copy of BridgeHistoryEntityState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,}) {
  return _then(BridgeHistoryEntityState_KnownActive(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BridgeChatActiveStatus,
  ));
}


}

/// @nodoc


class BridgeHistoryEntityState_KnownTerminal extends BridgeHistoryEntityState {
  const BridgeHistoryEntityState_KnownTerminal({required this.outcome}): super._();


 final  BridgeChatTerminalOutcome outcome;

/// Create a copy of BridgeHistoryEntityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryEntityState_KnownTerminalCopyWith<BridgeHistoryEntityState_KnownTerminal> get copyWith => _$BridgeHistoryEntityState_KnownTerminalCopyWithImpl<BridgeHistoryEntityState_KnownTerminal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEntityState_KnownTerminal&&(identical(other.outcome, outcome) || other.outcome == outcome));
}


@override
int get hashCode {
    return Object.hash(runtimeType,outcome);
}

@override
String toString() {
    return 'BridgeHistoryEntityState.knownTerminal(outcome: $outcome)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryEntityState_KnownTerminalCopyWith<$Res> implements $BridgeHistoryEntityStateCopyWith<$Res> {
  factory $BridgeHistoryEntityState_KnownTerminalCopyWith(BridgeHistoryEntityState_KnownTerminal value, $Res Function(BridgeHistoryEntityState_KnownTerminal) _then) = _$BridgeHistoryEntityState_KnownTerminalCopyWithImpl;
@useResult
$Res call({
 BridgeChatTerminalOutcome outcome
});




}
/// @nodoc
class _$BridgeHistoryEntityState_KnownTerminalCopyWithImpl<$Res>
    implements $BridgeHistoryEntityState_KnownTerminalCopyWith<$Res> {
  _$BridgeHistoryEntityState_KnownTerminalCopyWithImpl(this._self, this._then);

  final BridgeHistoryEntityState_KnownTerminal _self;
  final $Res Function(BridgeHistoryEntityState_KnownTerminal) _then;

/// Create a copy of BridgeHistoryEntityState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? outcome = null,}) {
  return _then(BridgeHistoryEntityState_KnownTerminal(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as BridgeChatTerminalOutcome,
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryEventsQuery_AllEvents value)?  allEvents,TResult Function( BridgeHistoryEventsQuery_Entity value)?  entity,TResult Function( BridgeHistoryEventsQuery_Turn value)?  turn,TResult Function( BridgeHistoryEventsQuery_Source value)?  source,TResult Function( BridgeHistoryEventsQuery_Call value)?  call,TResult Function( BridgeHistoryEventsQuery_Message value)?  message,TResult Function( BridgeHistoryEventsQuery_Attempt value)?  attempt,TResult Function( BridgeHistoryEventsQuery_Originals value)?  originals,TResult Function( BridgeHistoryEventsQuery_TextOriginals value)?  textOriginals,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents() when allEvents != null:
return allEvents(_that);case BridgeHistoryEventsQuery_Entity() when entity != null:
return entity(_that);case BridgeHistoryEventsQuery_Turn() when turn != null:
return turn(_that);case BridgeHistoryEventsQuery_Source() when source != null:
return source(_that);case BridgeHistoryEventsQuery_Call() when call != null:
return call(_that);case BridgeHistoryEventsQuery_Message() when message != null:
return message(_that);case BridgeHistoryEventsQuery_Attempt() when attempt != null:
return attempt(_that);case BridgeHistoryEventsQuery_Originals() when originals != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryEventsQuery_AllEvents value)  allEvents,required TResult Function( BridgeHistoryEventsQuery_Entity value)  entity,required TResult Function( BridgeHistoryEventsQuery_Turn value)  turn,required TResult Function( BridgeHistoryEventsQuery_Source value)  source,required TResult Function( BridgeHistoryEventsQuery_Call value)  call,required TResult Function( BridgeHistoryEventsQuery_Message value)  message,required TResult Function( BridgeHistoryEventsQuery_Attempt value)  attempt,required TResult Function( BridgeHistoryEventsQuery_Originals value)  originals,required TResult Function( BridgeHistoryEventsQuery_TextOriginals value)  textOriginals,}){
final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents():
return allEvents(_that);case BridgeHistoryEventsQuery_Entity():
return entity(_that);case BridgeHistoryEventsQuery_Turn():
return turn(_that);case BridgeHistoryEventsQuery_Source():
return source(_that);case BridgeHistoryEventsQuery_Call():
return call(_that);case BridgeHistoryEventsQuery_Message():
return message(_that);case BridgeHistoryEventsQuery_Attempt():
return attempt(_that);case BridgeHistoryEventsQuery_Originals():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryEventsQuery_AllEvents value)?  allEvents,TResult? Function( BridgeHistoryEventsQuery_Entity value)?  entity,TResult? Function( BridgeHistoryEventsQuery_Turn value)?  turn,TResult? Function( BridgeHistoryEventsQuery_Source value)?  source,TResult? Function( BridgeHistoryEventsQuery_Call value)?  call,TResult? Function( BridgeHistoryEventsQuery_Message value)?  message,TResult? Function( BridgeHistoryEventsQuery_Attempt value)?  attempt,TResult? Function( BridgeHistoryEventsQuery_Originals value)?  originals,TResult? Function( BridgeHistoryEventsQuery_TextOriginals value)?  textOriginals,}){
final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents() when allEvents != null:
return allEvents(_that);case BridgeHistoryEventsQuery_Entity() when entity != null:
return entity(_that);case BridgeHistoryEventsQuery_Turn() when turn != null:
return turn(_that);case BridgeHistoryEventsQuery_Source() when source != null:
return source(_that);case BridgeHistoryEventsQuery_Call() when call != null:
return call(_that);case BridgeHistoryEventsQuery_Message() when message != null:
return message(_that);case BridgeHistoryEventsQuery_Attempt() when attempt != null:
return attempt(_that);case BridgeHistoryEventsQuery_Originals() when originals != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  allEvents,TResult Function( String entityId)?  entity,TResult Function( String turnId)?  turn,TResult Function( BridgeChatSourceId source)?  source,TResult Function( String callId)?  call,TResult Function( String messageId)?  message,TResult Function( String runId,  String attemptId)?  attempt,TResult Function( String queryClass,  String? parentId)?  originals,TResult Function()?  textOriginals,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents() when allEvents != null:
return allEvents();case BridgeHistoryEventsQuery_Entity() when entity != null:
return entity(_that.entityId);case BridgeHistoryEventsQuery_Turn() when turn != null:
return turn(_that.turnId);case BridgeHistoryEventsQuery_Source() when source != null:
return source(_that.source);case BridgeHistoryEventsQuery_Call() when call != null:
return call(_that.callId);case BridgeHistoryEventsQuery_Message() when message != null:
return message(_that.messageId);case BridgeHistoryEventsQuery_Attempt() when attempt != null:
return attempt(_that.runId,_that.attemptId);case BridgeHistoryEventsQuery_Originals() when originals != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  allEvents,required TResult Function( String entityId)  entity,required TResult Function( String turnId)  turn,required TResult Function( BridgeChatSourceId source)  source,required TResult Function( String callId)  call,required TResult Function( String messageId)  message,required TResult Function( String runId,  String attemptId)  attempt,required TResult Function( String queryClass,  String? parentId)  originals,required TResult Function()  textOriginals,}) {final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents():
return allEvents();case BridgeHistoryEventsQuery_Entity():
return entity(_that.entityId);case BridgeHistoryEventsQuery_Turn():
return turn(_that.turnId);case BridgeHistoryEventsQuery_Source():
return source(_that.source);case BridgeHistoryEventsQuery_Call():
return call(_that.callId);case BridgeHistoryEventsQuery_Message():
return message(_that.messageId);case BridgeHistoryEventsQuery_Attempt():
return attempt(_that.runId,_that.attemptId);case BridgeHistoryEventsQuery_Originals():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  allEvents,TResult? Function( String entityId)?  entity,TResult? Function( String turnId)?  turn,TResult? Function( BridgeChatSourceId source)?  source,TResult? Function( String callId)?  call,TResult? Function( String messageId)?  message,TResult? Function( String runId,  String attemptId)?  attempt,TResult? Function( String queryClass,  String? parentId)?  originals,TResult? Function()?  textOriginals,}) {final _that = this;
switch (_that) {
case BridgeHistoryEventsQuery_AllEvents() when allEvents != null:
return allEvents();case BridgeHistoryEventsQuery_Entity() when entity != null:
return entity(_that.entityId);case BridgeHistoryEventsQuery_Turn() when turn != null:
return turn(_that.turnId);case BridgeHistoryEventsQuery_Source() when source != null:
return source(_that.source);case BridgeHistoryEventsQuery_Call() when call != null:
return call(_that.callId);case BridgeHistoryEventsQuery_Message() when message != null:
return message(_that.messageId);case BridgeHistoryEventsQuery_Attempt() when attempt != null:
return attempt(_that.runId,_that.attemptId);case BridgeHistoryEventsQuery_Originals() when originals != null:
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


class BridgeHistoryEventsQuery_Message extends BridgeHistoryEventsQuery {
  const BridgeHistoryEventsQuery_Message({required this.messageId}): super._();


 final  String messageId;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryEventsQuery_MessageCopyWith<BridgeHistoryEventsQuery_Message> get copyWith => _$BridgeHistoryEventsQuery_MessageCopyWithImpl<BridgeHistoryEventsQuery_Message>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery_Message&&(identical(other.messageId, messageId) || other.messageId == messageId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,messageId);
}

@override
String toString() {
    return 'BridgeHistoryEventsQuery.message(messageId: $messageId)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryEventsQuery_MessageCopyWith<$Res> implements $BridgeHistoryEventsQueryCopyWith<$Res> {
  factory $BridgeHistoryEventsQuery_MessageCopyWith(BridgeHistoryEventsQuery_Message value, $Res Function(BridgeHistoryEventsQuery_Message) _then) = _$BridgeHistoryEventsQuery_MessageCopyWithImpl;
@useResult
$Res call({
 String messageId
});




}
/// @nodoc
class _$BridgeHistoryEventsQuery_MessageCopyWithImpl<$Res>
    implements $BridgeHistoryEventsQuery_MessageCopyWith<$Res> {
  _$BridgeHistoryEventsQuery_MessageCopyWithImpl(this._self, this._then);

  final BridgeHistoryEventsQuery_Message _self;
  final $Res Function(BridgeHistoryEventsQuery_Message) _then;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? messageId = null,}) {
  return _then(BridgeHistoryEventsQuery_Message(
messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeHistoryEventsQuery_Attempt extends BridgeHistoryEventsQuery {
  const BridgeHistoryEventsQuery_Attempt({required this.runId, required this.attemptId}): super._();


 final  String runId;
 final  String attemptId;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryEventsQuery_AttemptCopyWith<BridgeHistoryEventsQuery_Attempt> get copyWith => _$BridgeHistoryEventsQuery_AttemptCopyWithImpl<BridgeHistoryEventsQuery_Attempt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryEventsQuery_Attempt&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,runId,attemptId);
}

@override
String toString() {
    return 'BridgeHistoryEventsQuery.attempt(runId: $runId, attemptId: $attemptId)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryEventsQuery_AttemptCopyWith<$Res> implements $BridgeHistoryEventsQueryCopyWith<$Res> {
  factory $BridgeHistoryEventsQuery_AttemptCopyWith(BridgeHistoryEventsQuery_Attempt value, $Res Function(BridgeHistoryEventsQuery_Attempt) _then) = _$BridgeHistoryEventsQuery_AttemptCopyWithImpl;
@useResult
$Res call({
 String runId, String attemptId
});




}
/// @nodoc
class _$BridgeHistoryEventsQuery_AttemptCopyWithImpl<$Res>
    implements $BridgeHistoryEventsQuery_AttemptCopyWith<$Res> {
  _$BridgeHistoryEventsQuery_AttemptCopyWithImpl(this._self, this._then);

  final BridgeHistoryEventsQuery_Attempt _self;
  final $Res Function(BridgeHistoryEventsQuery_Attempt) _then;

/// Create a copy of BridgeHistoryEventsQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runId = null,Object? attemptId = null,}) {
  return _then(BridgeHistoryEventsQuery_Attempt(
runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
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
mixin _$BridgeHistoryObservation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryObservation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryObservation()';
}


}

/// @nodoc
class $BridgeHistoryObservationCopyWith<$Res>  {
$BridgeHistoryObservationCopyWith(BridgeHistoryObservation _, $Res Function(BridgeHistoryObservation) __);
}


/// Adds pattern-matching-related methods to [BridgeHistoryObservation].
extension BridgeHistoryObservationPatterns on BridgeHistoryObservation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryObservation_Original value)?  original,TResult Function( BridgeHistoryObservation_Boundary value)?  boundary,TResult Function( BridgeHistoryObservation_UnavailableLegacy value)?  unavailableLegacy,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryObservation_Original() when original != null:
return original(_that);case BridgeHistoryObservation_Boundary() when boundary != null:
return boundary(_that);case BridgeHistoryObservation_UnavailableLegacy() when unavailableLegacy != null:
return unavailableLegacy(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryObservation_Original value)  original,required TResult Function( BridgeHistoryObservation_Boundary value)  boundary,required TResult Function( BridgeHistoryObservation_UnavailableLegacy value)  unavailableLegacy,}){
final _that = this;
switch (_that) {
case BridgeHistoryObservation_Original():
return original(_that);case BridgeHistoryObservation_Boundary():
return boundary(_that);case BridgeHistoryObservation_UnavailableLegacy():
return unavailableLegacy(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryObservation_Original value)?  original,TResult? Function( BridgeHistoryObservation_Boundary value)?  boundary,TResult? Function( BridgeHistoryObservation_UnavailableLegacy value)?  unavailableLegacy,}){
final _that = this;
switch (_that) {
case BridgeHistoryObservation_Original() when original != null:
return original(_that);case BridgeHistoryObservation_Boundary() when boundary != null:
return boundary(_that);case BridgeHistoryObservation_UnavailableLegacy() when unavailableLegacy != null:
return unavailableLegacy(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  original,TResult Function( PlatformInt64? capturedAt)?  boundary,TResult Function( PlatformInt64? capturedAt)?  unavailableLegacy,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryObservation_Original() when original != null:
return original();case BridgeHistoryObservation_Boundary() when boundary != null:
return boundary(_that.capturedAt);case BridgeHistoryObservation_UnavailableLegacy() when unavailableLegacy != null:
return unavailableLegacy(_that.capturedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  original,required TResult Function( PlatformInt64? capturedAt)  boundary,required TResult Function( PlatformInt64? capturedAt)  unavailableLegacy,}) {final _that = this;
switch (_that) {
case BridgeHistoryObservation_Original():
return original();case BridgeHistoryObservation_Boundary():
return boundary(_that.capturedAt);case BridgeHistoryObservation_UnavailableLegacy():
return unavailableLegacy(_that.capturedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  original,TResult? Function( PlatformInt64? capturedAt)?  boundary,TResult? Function( PlatformInt64? capturedAt)?  unavailableLegacy,}) {final _that = this;
switch (_that) {
case BridgeHistoryObservation_Original() when original != null:
return original();case BridgeHistoryObservation_Boundary() when boundary != null:
return boundary(_that.capturedAt);case BridgeHistoryObservation_UnavailableLegacy() when unavailableLegacy != null:
return unavailableLegacy(_that.capturedAt);case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistoryObservation_Original extends BridgeHistoryObservation {
  const BridgeHistoryObservation_Original(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryObservation_Original);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryObservation.original()';
}


}




/// @nodoc


class BridgeHistoryObservation_Boundary extends BridgeHistoryObservation {
  const BridgeHistoryObservation_Boundary({this.capturedAt}): super._();


 final  PlatformInt64? capturedAt;

/// Create a copy of BridgeHistoryObservation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryObservation_BoundaryCopyWith<BridgeHistoryObservation_Boundary> get copyWith => _$BridgeHistoryObservation_BoundaryCopyWithImpl<BridgeHistoryObservation_Boundary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryObservation_Boundary&&(identical(other.capturedAt, capturedAt) || other.capturedAt == capturedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,capturedAt);
}

@override
String toString() {
    return 'BridgeHistoryObservation.boundary(capturedAt: $capturedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryObservation_BoundaryCopyWith<$Res> implements $BridgeHistoryObservationCopyWith<$Res> {
  factory $BridgeHistoryObservation_BoundaryCopyWith(BridgeHistoryObservation_Boundary value, $Res Function(BridgeHistoryObservation_Boundary) _then) = _$BridgeHistoryObservation_BoundaryCopyWithImpl;
@useResult
$Res call({
 PlatformInt64? capturedAt
});




}
/// @nodoc
class _$BridgeHistoryObservation_BoundaryCopyWithImpl<$Res>
    implements $BridgeHistoryObservation_BoundaryCopyWith<$Res> {
  _$BridgeHistoryObservation_BoundaryCopyWithImpl(this._self, this._then);

  final BridgeHistoryObservation_Boundary _self;
  final $Res Function(BridgeHistoryObservation_Boundary) _then;

/// Create a copy of BridgeHistoryObservation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? capturedAt = freezed,}) {
  return _then(BridgeHistoryObservation_Boundary(
capturedAt: freezed == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeHistoryObservation_UnavailableLegacy extends BridgeHistoryObservation {
  const BridgeHistoryObservation_UnavailableLegacy({this.capturedAt}): super._();


 final  PlatformInt64? capturedAt;

/// Create a copy of BridgeHistoryObservation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryObservation_UnavailableLegacyCopyWith<BridgeHistoryObservation_UnavailableLegacy> get copyWith => _$BridgeHistoryObservation_UnavailableLegacyCopyWithImpl<BridgeHistoryObservation_UnavailableLegacy>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryObservation_UnavailableLegacy&&(identical(other.capturedAt, capturedAt) || other.capturedAt == capturedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,capturedAt);
}

@override
String toString() {
    return 'BridgeHistoryObservation.unavailableLegacy(capturedAt: $capturedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryObservation_UnavailableLegacyCopyWith<$Res> implements $BridgeHistoryObservationCopyWith<$Res> {
  factory $BridgeHistoryObservation_UnavailableLegacyCopyWith(BridgeHistoryObservation_UnavailableLegacy value, $Res Function(BridgeHistoryObservation_UnavailableLegacy) _then) = _$BridgeHistoryObservation_UnavailableLegacyCopyWithImpl;
@useResult
$Res call({
 PlatformInt64? capturedAt
});




}
/// @nodoc
class _$BridgeHistoryObservation_UnavailableLegacyCopyWithImpl<$Res>
    implements $BridgeHistoryObservation_UnavailableLegacyCopyWith<$Res> {
  _$BridgeHistoryObservation_UnavailableLegacyCopyWithImpl(this._self, this._then);

  final BridgeHistoryObservation_UnavailableLegacy _self;
  final $Res Function(BridgeHistoryObservation_UnavailableLegacy) _then;

/// Create a copy of BridgeHistoryObservation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? capturedAt = freezed,}) {
  return _then(BridgeHistoryObservation_UnavailableLegacy(
capturedAt: freezed == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc
mixin _$BridgeHistoryRowHead {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as BridgeHistoryRowHead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryRowHead&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as BridgeHistoryRowHead;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as BridgeHistoryRowHead;
  return 'BridgeHistoryRowHead(field0: ${_this.field0})';
}


}

/// @nodoc
class $BridgeHistoryRowHeadCopyWith<$Res>  {
$BridgeHistoryRowHeadCopyWith(BridgeHistoryRowHead _, $Res Function(BridgeHistoryRowHead) __);
}


/// Adds pattern-matching-related methods to [BridgeHistoryRowHead].
extension BridgeHistoryRowHeadPatterns on BridgeHistoryRowHead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryRowHead_Work value)?  work,TResult Function( BridgeHistoryRowHead_Single value)?  single,TResult Function( BridgeHistoryRowHead_Member value)?  member,TResult Function( BridgeHistoryRowHead_Turn value)?  turn,TResult Function( BridgeHistoryRowHead_Source value)?  source,TResult Function( BridgeHistoryRowHead_Cost value)?  cost,TResult Function( BridgeHistoryRowHead_Accounting value)?  accounting,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryRowHead_Work() when work != null:
return work(_that);case BridgeHistoryRowHead_Single() when single != null:
return single(_that);case BridgeHistoryRowHead_Member() when member != null:
return member(_that);case BridgeHistoryRowHead_Turn() when turn != null:
return turn(_that);case BridgeHistoryRowHead_Source() when source != null:
return source(_that);case BridgeHistoryRowHead_Cost() when cost != null:
return cost(_that);case BridgeHistoryRowHead_Accounting() when accounting != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryRowHead_Work value)  work,required TResult Function( BridgeHistoryRowHead_Single value)  single,required TResult Function( BridgeHistoryRowHead_Member value)  member,required TResult Function( BridgeHistoryRowHead_Turn value)  turn,required TResult Function( BridgeHistoryRowHead_Source value)  source,required TResult Function( BridgeHistoryRowHead_Cost value)  cost,required TResult Function( BridgeHistoryRowHead_Accounting value)  accounting,}){
final _that = this;
switch (_that) {
case BridgeHistoryRowHead_Work():
return work(_that);case BridgeHistoryRowHead_Single():
return single(_that);case BridgeHistoryRowHead_Member():
return member(_that);case BridgeHistoryRowHead_Turn():
return turn(_that);case BridgeHistoryRowHead_Source():
return source(_that);case BridgeHistoryRowHead_Cost():
return cost(_that);case BridgeHistoryRowHead_Accounting():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryRowHead_Work value)?  work,TResult? Function( BridgeHistoryRowHead_Single value)?  single,TResult? Function( BridgeHistoryRowHead_Member value)?  member,TResult? Function( BridgeHistoryRowHead_Turn value)?  turn,TResult? Function( BridgeHistoryRowHead_Source value)?  source,TResult? Function( BridgeHistoryRowHead_Cost value)?  cost,TResult? Function( BridgeHistoryRowHead_Accounting value)?  accounting,}){
final _that = this;
switch (_that) {
case BridgeHistoryRowHead_Work() when work != null:
return work(_that);case BridgeHistoryRowHead_Single() when single != null:
return single(_that);case BridgeHistoryRowHead_Member() when member != null:
return member(_that);case BridgeHistoryRowHead_Turn() when turn != null:
return turn(_that);case BridgeHistoryRowHead_Source() when source != null:
return source(_that);case BridgeHistoryRowHead_Cost() when cost != null:
return cost(_that);case BridgeHistoryRowHead_Accounting() when accounting != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeHistoryWorkHead field0)?  work,TResult Function( BridgeHistoryEntityHead field0)?  single,TResult Function( BridgeHistoryEntityHead field0)?  member,TResult Function( BridgeHistoryTurnHead field0)?  turn,TResult Function( BridgeHistorySourceHead field0)?  source,TResult Function( BridgeHistoryCostHead field0)?  cost,TResult Function( BridgeHistoryAccountingHead field0)?  accounting,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryRowHead_Work() when work != null:
return work(_that.field0);case BridgeHistoryRowHead_Single() when single != null:
return single(_that.field0);case BridgeHistoryRowHead_Member() when member != null:
return member(_that.field0);case BridgeHistoryRowHead_Turn() when turn != null:
return turn(_that.field0);case BridgeHistoryRowHead_Source() when source != null:
return source(_that.field0);case BridgeHistoryRowHead_Cost() when cost != null:
return cost(_that.field0);case BridgeHistoryRowHead_Accounting() when accounting != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeHistoryWorkHead field0)  work,required TResult Function( BridgeHistoryEntityHead field0)  single,required TResult Function( BridgeHistoryEntityHead field0)  member,required TResult Function( BridgeHistoryTurnHead field0)  turn,required TResult Function( BridgeHistorySourceHead field0)  source,required TResult Function( BridgeHistoryCostHead field0)  cost,required TResult Function( BridgeHistoryAccountingHead field0)  accounting,}) {final _that = this;
switch (_that) {
case BridgeHistoryRowHead_Work():
return work(_that.field0);case BridgeHistoryRowHead_Single():
return single(_that.field0);case BridgeHistoryRowHead_Member():
return member(_that.field0);case BridgeHistoryRowHead_Turn():
return turn(_that.field0);case BridgeHistoryRowHead_Source():
return source(_that.field0);case BridgeHistoryRowHead_Cost():
return cost(_that.field0);case BridgeHistoryRowHead_Accounting():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryWorkHead field0)?  work,TResult? Function( BridgeHistoryEntityHead field0)?  single,TResult? Function( BridgeHistoryEntityHead field0)?  member,TResult? Function( BridgeHistoryTurnHead field0)?  turn,TResult? Function( BridgeHistorySourceHead field0)?  source,TResult? Function( BridgeHistoryCostHead field0)?  cost,TResult? Function( BridgeHistoryAccountingHead field0)?  accounting,}) {final _that = this;
switch (_that) {
case BridgeHistoryRowHead_Work() when work != null:
return work(_that.field0);case BridgeHistoryRowHead_Single() when single != null:
return single(_that.field0);case BridgeHistoryRowHead_Member() when member != null:
return member(_that.field0);case BridgeHistoryRowHead_Turn() when turn != null:
return turn(_that.field0);case BridgeHistoryRowHead_Source() when source != null:
return source(_that.field0);case BridgeHistoryRowHead_Cost() when cost != null:
return cost(_that.field0);case BridgeHistoryRowHead_Accounting() when accounting != null:
return accounting(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistoryRowHead_Work extends BridgeHistoryRowHead {
  const BridgeHistoryRowHead_Work(this.field0): super._();


@override final  BridgeHistoryWorkHead field0;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryRowHead_WorkCopyWith<BridgeHistoryRowHead_Work> get copyWith => _$BridgeHistoryRowHead_WorkCopyWithImpl<BridgeHistoryRowHead_Work>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryRowHead_Work&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryRowHead.work(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryRowHead_WorkCopyWith<$Res> implements $BridgeHistoryRowHeadCopyWith<$Res> {
  factory $BridgeHistoryRowHead_WorkCopyWith(BridgeHistoryRowHead_Work value, $Res Function(BridgeHistoryRowHead_Work) _then) = _$BridgeHistoryRowHead_WorkCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryWorkHead field0
});




}
/// @nodoc
class _$BridgeHistoryRowHead_WorkCopyWithImpl<$Res>
    implements $BridgeHistoryRowHead_WorkCopyWith<$Res> {
  _$BridgeHistoryRowHead_WorkCopyWithImpl(this._self, this._then);

  final BridgeHistoryRowHead_Work _self;
  final $Res Function(BridgeHistoryRowHead_Work) _then;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryRowHead_Work(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryWorkHead,
  ));
}


}

/// @nodoc


class BridgeHistoryRowHead_Single extends BridgeHistoryRowHead {
  const BridgeHistoryRowHead_Single(this.field0): super._();


@override final  BridgeHistoryEntityHead field0;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryRowHead_SingleCopyWith<BridgeHistoryRowHead_Single> get copyWith => _$BridgeHistoryRowHead_SingleCopyWithImpl<BridgeHistoryRowHead_Single>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryRowHead_Single&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryRowHead.single(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryRowHead_SingleCopyWith<$Res> implements $BridgeHistoryRowHeadCopyWith<$Res> {
  factory $BridgeHistoryRowHead_SingleCopyWith(BridgeHistoryRowHead_Single value, $Res Function(BridgeHistoryRowHead_Single) _then) = _$BridgeHistoryRowHead_SingleCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryEntityHead field0
});




}
/// @nodoc
class _$BridgeHistoryRowHead_SingleCopyWithImpl<$Res>
    implements $BridgeHistoryRowHead_SingleCopyWith<$Res> {
  _$BridgeHistoryRowHead_SingleCopyWithImpl(this._self, this._then);

  final BridgeHistoryRowHead_Single _self;
  final $Res Function(BridgeHistoryRowHead_Single) _then;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryRowHead_Single(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryEntityHead,
  ));
}


}

/// @nodoc


class BridgeHistoryRowHead_Member extends BridgeHistoryRowHead {
  const BridgeHistoryRowHead_Member(this.field0): super._();


@override final  BridgeHistoryEntityHead field0;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryRowHead_MemberCopyWith<BridgeHistoryRowHead_Member> get copyWith => _$BridgeHistoryRowHead_MemberCopyWithImpl<BridgeHistoryRowHead_Member>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryRowHead_Member&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryRowHead.member(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryRowHead_MemberCopyWith<$Res> implements $BridgeHistoryRowHeadCopyWith<$Res> {
  factory $BridgeHistoryRowHead_MemberCopyWith(BridgeHistoryRowHead_Member value, $Res Function(BridgeHistoryRowHead_Member) _then) = _$BridgeHistoryRowHead_MemberCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryEntityHead field0
});




}
/// @nodoc
class _$BridgeHistoryRowHead_MemberCopyWithImpl<$Res>
    implements $BridgeHistoryRowHead_MemberCopyWith<$Res> {
  _$BridgeHistoryRowHead_MemberCopyWithImpl(this._self, this._then);

  final BridgeHistoryRowHead_Member _self;
  final $Res Function(BridgeHistoryRowHead_Member) _then;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryRowHead_Member(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryEntityHead,
  ));
}


}

/// @nodoc


class BridgeHistoryRowHead_Turn extends BridgeHistoryRowHead {
  const BridgeHistoryRowHead_Turn(this.field0): super._();


@override final  BridgeHistoryTurnHead field0;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryRowHead_TurnCopyWith<BridgeHistoryRowHead_Turn> get copyWith => _$BridgeHistoryRowHead_TurnCopyWithImpl<BridgeHistoryRowHead_Turn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryRowHead_Turn&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryRowHead.turn(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryRowHead_TurnCopyWith<$Res> implements $BridgeHistoryRowHeadCopyWith<$Res> {
  factory $BridgeHistoryRowHead_TurnCopyWith(BridgeHistoryRowHead_Turn value, $Res Function(BridgeHistoryRowHead_Turn) _then) = _$BridgeHistoryRowHead_TurnCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryTurnHead field0
});




}
/// @nodoc
class _$BridgeHistoryRowHead_TurnCopyWithImpl<$Res>
    implements $BridgeHistoryRowHead_TurnCopyWith<$Res> {
  _$BridgeHistoryRowHead_TurnCopyWithImpl(this._self, this._then);

  final BridgeHistoryRowHead_Turn _self;
  final $Res Function(BridgeHistoryRowHead_Turn) _then;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryRowHead_Turn(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryTurnHead,
  ));
}


}

/// @nodoc


class BridgeHistoryRowHead_Source extends BridgeHistoryRowHead {
  const BridgeHistoryRowHead_Source(this.field0): super._();


@override final  BridgeHistorySourceHead field0;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryRowHead_SourceCopyWith<BridgeHistoryRowHead_Source> get copyWith => _$BridgeHistoryRowHead_SourceCopyWithImpl<BridgeHistoryRowHead_Source>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryRowHead_Source&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryRowHead.source(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryRowHead_SourceCopyWith<$Res> implements $BridgeHistoryRowHeadCopyWith<$Res> {
  factory $BridgeHistoryRowHead_SourceCopyWith(BridgeHistoryRowHead_Source value, $Res Function(BridgeHistoryRowHead_Source) _then) = _$BridgeHistoryRowHead_SourceCopyWithImpl;
@useResult
$Res call({
 BridgeHistorySourceHead field0
});




}
/// @nodoc
class _$BridgeHistoryRowHead_SourceCopyWithImpl<$Res>
    implements $BridgeHistoryRowHead_SourceCopyWith<$Res> {
  _$BridgeHistoryRowHead_SourceCopyWithImpl(this._self, this._then);

  final BridgeHistoryRowHead_Source _self;
  final $Res Function(BridgeHistoryRowHead_Source) _then;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryRowHead_Source(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistorySourceHead,
  ));
}


}

/// @nodoc


class BridgeHistoryRowHead_Cost extends BridgeHistoryRowHead {
  const BridgeHistoryRowHead_Cost(this.field0): super._();


@override final  BridgeHistoryCostHead field0;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryRowHead_CostCopyWith<BridgeHistoryRowHead_Cost> get copyWith => _$BridgeHistoryRowHead_CostCopyWithImpl<BridgeHistoryRowHead_Cost>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryRowHead_Cost&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryRowHead.cost(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryRowHead_CostCopyWith<$Res> implements $BridgeHistoryRowHeadCopyWith<$Res> {
  factory $BridgeHistoryRowHead_CostCopyWith(BridgeHistoryRowHead_Cost value, $Res Function(BridgeHistoryRowHead_Cost) _then) = _$BridgeHistoryRowHead_CostCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryCostHead field0
});




}
/// @nodoc
class _$BridgeHistoryRowHead_CostCopyWithImpl<$Res>
    implements $BridgeHistoryRowHead_CostCopyWith<$Res> {
  _$BridgeHistoryRowHead_CostCopyWithImpl(this._self, this._then);

  final BridgeHistoryRowHead_Cost _self;
  final $Res Function(BridgeHistoryRowHead_Cost) _then;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryRowHead_Cost(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryCostHead,
  ));
}


}

/// @nodoc


class BridgeHistoryRowHead_Accounting extends BridgeHistoryRowHead {
  const BridgeHistoryRowHead_Accounting(this.field0): super._();


@override final  BridgeHistoryAccountingHead field0;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryRowHead_AccountingCopyWith<BridgeHistoryRowHead_Accounting> get copyWith => _$BridgeHistoryRowHead_AccountingCopyWithImpl<BridgeHistoryRowHead_Accounting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryRowHead_Accounting&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeHistoryRowHead.accounting(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryRowHead_AccountingCopyWith<$Res> implements $BridgeHistoryRowHeadCopyWith<$Res> {
  factory $BridgeHistoryRowHead_AccountingCopyWith(BridgeHistoryRowHead_Accounting value, $Res Function(BridgeHistoryRowHead_Accounting) _then) = _$BridgeHistoryRowHead_AccountingCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryAccountingHead field0
});




}
/// @nodoc
class _$BridgeHistoryRowHead_AccountingCopyWithImpl<$Res>
    implements $BridgeHistoryRowHead_AccountingCopyWith<$Res> {
  _$BridgeHistoryRowHead_AccountingCopyWithImpl(this._self, this._then);

  final BridgeHistoryRowHead_Accounting _self;
  final $Res Function(BridgeHistoryRowHead_Accounting) _then;

/// Create a copy of BridgeHistoryRowHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeHistoryRowHead_Accounting(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeHistoryAccountingHead,
  ));
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
mixin _$BridgeHistoryWaitHead {

 Object get presentation;



@override
bool operator ==(Object other) {
  final _this = this as BridgeHistoryWaitHead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryWaitHead&&const DeepCollectionEquality().equals(other.presentation, _this.presentation));
}


@override
int get hashCode {
  final _this = this as BridgeHistoryWaitHead;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.presentation));
}

@override
String toString() {
  final _this = this as BridgeHistoryWaitHead;
  return 'BridgeHistoryWaitHead(presentation: ${_this.presentation})';
}


}

/// @nodoc
class $BridgeHistoryWaitHeadCopyWith<$Res>  {
$BridgeHistoryWaitHeadCopyWith(BridgeHistoryWaitHead _, $Res Function(BridgeHistoryWaitHead) __);
}


/// Adds pattern-matching-related methods to [BridgeHistoryWaitHead].
extension BridgeHistoryWaitHeadPatterns on BridgeHistoryWaitHead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryWaitHead_Inline value)?  inline,TResult Function( BridgeHistoryWaitHead_Deferred value)?  deferred_,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryWaitHead_Inline() when inline != null:
return inline(_that);case BridgeHistoryWaitHead_Deferred() when deferred_ != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryWaitHead_Inline value)  inline,required TResult Function( BridgeHistoryWaitHead_Deferred value)  deferred_,}){
final _that = this;
switch (_that) {
case BridgeHistoryWaitHead_Inline():
return inline(_that);case BridgeHistoryWaitHead_Deferred():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryWaitHead_Inline value)?  inline,TResult? Function( BridgeHistoryWaitHead_Deferred value)?  deferred_,}){
final _that = this;
switch (_that) {
case BridgeHistoryWaitHead_Inline() when inline != null:
return inline(_that);case BridgeHistoryWaitHead_Deferred() when deferred_ != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadWaitPresentation presentation)?  inline,TResult Function( BridgeHistoryWaitIntent intent,  BridgeHistoryWaitState state,  bool? messagesReady,  BridgeHistoryEventBodyRef presentation)?  deferred_,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryWaitHead_Inline() when inline != null:
return inline(_that.presentation);case BridgeHistoryWaitHead_Deferred() when deferred_ != null:
return deferred_(_that.intent,_that.state,_that.messagesReady,_that.presentation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadWaitPresentation presentation)  inline,required TResult Function( BridgeHistoryWaitIntent intent,  BridgeHistoryWaitState state,  bool? messagesReady,  BridgeHistoryEventBodyRef presentation)  deferred_,}) {final _that = this;
switch (_that) {
case BridgeHistoryWaitHead_Inline():
return inline(_that.presentation);case BridgeHistoryWaitHead_Deferred():
return deferred_(_that.intent,_that.state,_that.messagesReady,_that.presentation);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadWaitPresentation presentation)?  inline,TResult? Function( BridgeHistoryWaitIntent intent,  BridgeHistoryWaitState state,  bool? messagesReady,  BridgeHistoryEventBodyRef presentation)?  deferred_,}) {final _that = this;
switch (_that) {
case BridgeHistoryWaitHead_Inline() when inline != null:
return inline(_that.presentation);case BridgeHistoryWaitHead_Deferred() when deferred_ != null:
return deferred_(_that.intent,_that.state,_that.messagesReady,_that.presentation);case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistoryWaitHead_Inline extends BridgeHistoryWaitHead {
  const BridgeHistoryWaitHead_Inline({required this.presentation}): super._();


@override final  BridgeThreadWaitPresentation presentation;

/// Create a copy of BridgeHistoryWaitHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryWaitHead_InlineCopyWith<BridgeHistoryWaitHead_Inline> get copyWith => _$BridgeHistoryWaitHead_InlineCopyWithImpl<BridgeHistoryWaitHead_Inline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryWaitHead_Inline&&(identical(other.presentation, presentation) || other.presentation == presentation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,presentation);
}

@override
String toString() {
    return 'BridgeHistoryWaitHead.inline(presentation: $presentation)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryWaitHead_InlineCopyWith<$Res> implements $BridgeHistoryWaitHeadCopyWith<$Res> {
  factory $BridgeHistoryWaitHead_InlineCopyWith(BridgeHistoryWaitHead_Inline value, $Res Function(BridgeHistoryWaitHead_Inline) _then) = _$BridgeHistoryWaitHead_InlineCopyWithImpl;
@useResult
$Res call({
 BridgeThreadWaitPresentation presentation
});




}
/// @nodoc
class _$BridgeHistoryWaitHead_InlineCopyWithImpl<$Res>
    implements $BridgeHistoryWaitHead_InlineCopyWith<$Res> {
  _$BridgeHistoryWaitHead_InlineCopyWithImpl(this._self, this._then);

  final BridgeHistoryWaitHead_Inline _self;
  final $Res Function(BridgeHistoryWaitHead_Inline) _then;

/// Create a copy of BridgeHistoryWaitHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? presentation = null,}) {
  return _then(BridgeHistoryWaitHead_Inline(
presentation: null == presentation ? _self.presentation : presentation // ignore: cast_nullable_to_non_nullable
as BridgeThreadWaitPresentation,
  ));
}


}

/// @nodoc


class BridgeHistoryWaitHead_Deferred extends BridgeHistoryWaitHead {
  const BridgeHistoryWaitHead_Deferred({required this.intent, required this.state, this.messagesReady, required this.presentation}): super._();


 final  BridgeHistoryWaitIntent intent;
 final  BridgeHistoryWaitState state;
 final  bool? messagesReady;
@override final  BridgeHistoryEventBodyRef presentation;

/// Create a copy of BridgeHistoryWaitHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryWaitHead_DeferredCopyWith<BridgeHistoryWaitHead_Deferred> get copyWith => _$BridgeHistoryWaitHead_DeferredCopyWithImpl<BridgeHistoryWaitHead_Deferred>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryWaitHead_Deferred&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.state, state) || other.state == state)&&(identical(other.messagesReady, messagesReady) || other.messagesReady == messagesReady)&&(identical(other.presentation, presentation) || other.presentation == presentation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,state,messagesReady,presentation);
}

@override
String toString() {
    return 'BridgeHistoryWaitHead.deferred_(intent: $intent, state: $state, messagesReady: $messagesReady, presentation: $presentation)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryWaitHead_DeferredCopyWith<$Res> implements $BridgeHistoryWaitHeadCopyWith<$Res> {
  factory $BridgeHistoryWaitHead_DeferredCopyWith(BridgeHistoryWaitHead_Deferred value, $Res Function(BridgeHistoryWaitHead_Deferred) _then) = _$BridgeHistoryWaitHead_DeferredCopyWithImpl;
@useResult
$Res call({
 BridgeHistoryWaitIntent intent, BridgeHistoryWaitState state, bool? messagesReady, BridgeHistoryEventBodyRef presentation
});


$BridgeHistoryWaitIntentCopyWith<$Res> get intent;

}
/// @nodoc
class _$BridgeHistoryWaitHead_DeferredCopyWithImpl<$Res>
    implements $BridgeHistoryWaitHead_DeferredCopyWith<$Res> {
  _$BridgeHistoryWaitHead_DeferredCopyWithImpl(this._self, this._then);

  final BridgeHistoryWaitHead_Deferred _self;
  final $Res Function(BridgeHistoryWaitHead_Deferred) _then;

/// Create a copy of BridgeHistoryWaitHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? state = null,Object? messagesReady = freezed,Object? presentation = null,}) {
  return _then(BridgeHistoryWaitHead_Deferred(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as BridgeHistoryWaitIntent,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeHistoryWaitState,messagesReady: freezed == messagesReady ? _self.messagesReady : messagesReady // ignore: cast_nullable_to_non_nullable
as bool?,presentation: null == presentation ? _self.presentation : presentation // ignore: cast_nullable_to_non_nullable
as BridgeHistoryEventBodyRef,
  ));
}

/// Create a copy of BridgeHistoryWaitHead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeHistoryWaitIntentCopyWith<$Res> get intent {

  return $BridgeHistoryWaitIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}
}

/// @nodoc
mixin _$BridgeHistoryWaitIntent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryWaitIntent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeHistoryWaitIntent()';
}


}

/// @nodoc
class $BridgeHistoryWaitIntentCopyWith<$Res>  {
$BridgeHistoryWaitIntentCopyWith(BridgeHistoryWaitIntent _, $Res Function(BridgeHistoryWaitIntent) __);
}


/// Adds pattern-matching-related methods to [BridgeHistoryWaitIntent].
extension BridgeHistoryWaitIntentPatterns on BridgeHistoryWaitIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeHistoryWaitIntent_Events value)?  events,TResult Function( BridgeHistoryWaitIntent_Timer value)?  timer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeHistoryWaitIntent_Events() when events != null:
return events(_that);case BridgeHistoryWaitIntent_Timer() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeHistoryWaitIntent_Events value)  events,required TResult Function( BridgeHistoryWaitIntent_Timer value)  timer,}){
final _that = this;
switch (_that) {
case BridgeHistoryWaitIntent_Events():
return events(_that);case BridgeHistoryWaitIntent_Timer():
return timer(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeHistoryWaitIntent_Events value)?  events,TResult? Function( BridgeHistoryWaitIntent_Timer value)?  timer,}){
final _that = this;
switch (_that) {
case BridgeHistoryWaitIntent_Events() when events != null:
return events(_that);case BridgeHistoryWaitIntent_Timer() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt targetCount,  BigInt timeoutMs)?  events,TResult Function( BigInt durationMs)?  timer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeHistoryWaitIntent_Events() when events != null:
return events(_that.targetCount,_that.timeoutMs);case BridgeHistoryWaitIntent_Timer() when timer != null:
return timer(_that.durationMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt targetCount,  BigInt timeoutMs)  events,required TResult Function( BigInt durationMs)  timer,}) {final _that = this;
switch (_that) {
case BridgeHistoryWaitIntent_Events():
return events(_that.targetCount,_that.timeoutMs);case BridgeHistoryWaitIntent_Timer():
return timer(_that.durationMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt targetCount,  BigInt timeoutMs)?  events,TResult? Function( BigInt durationMs)?  timer,}) {final _that = this;
switch (_that) {
case BridgeHistoryWaitIntent_Events() when events != null:
return events(_that.targetCount,_that.timeoutMs);case BridgeHistoryWaitIntent_Timer() when timer != null:
return timer(_that.durationMs);case _:
  return null;

}
}

}

/// @nodoc


class BridgeHistoryWaitIntent_Events extends BridgeHistoryWaitIntent {
  const BridgeHistoryWaitIntent_Events({required this.targetCount, required this.timeoutMs}): super._();


 final  BigInt targetCount;
 final  BigInt timeoutMs;

/// Create a copy of BridgeHistoryWaitIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryWaitIntent_EventsCopyWith<BridgeHistoryWaitIntent_Events> get copyWith => _$BridgeHistoryWaitIntent_EventsCopyWithImpl<BridgeHistoryWaitIntent_Events>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryWaitIntent_Events&&(identical(other.targetCount, targetCount) || other.targetCount == targetCount)&&(identical(other.timeoutMs, timeoutMs) || other.timeoutMs == timeoutMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,targetCount,timeoutMs);
}

@override
String toString() {
    return 'BridgeHistoryWaitIntent.events(targetCount: $targetCount, timeoutMs: $timeoutMs)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryWaitIntent_EventsCopyWith<$Res> implements $BridgeHistoryWaitIntentCopyWith<$Res> {
  factory $BridgeHistoryWaitIntent_EventsCopyWith(BridgeHistoryWaitIntent_Events value, $Res Function(BridgeHistoryWaitIntent_Events) _then) = _$BridgeHistoryWaitIntent_EventsCopyWithImpl;
@useResult
$Res call({
 BigInt targetCount, BigInt timeoutMs
});




}
/// @nodoc
class _$BridgeHistoryWaitIntent_EventsCopyWithImpl<$Res>
    implements $BridgeHistoryWaitIntent_EventsCopyWith<$Res> {
  _$BridgeHistoryWaitIntent_EventsCopyWithImpl(this._self, this._then);

  final BridgeHistoryWaitIntent_Events _self;
  final $Res Function(BridgeHistoryWaitIntent_Events) _then;

/// Create a copy of BridgeHistoryWaitIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetCount = null,Object? timeoutMs = null,}) {
  return _then(BridgeHistoryWaitIntent_Events(
targetCount: null == targetCount ? _self.targetCount : targetCount // ignore: cast_nullable_to_non_nullable
as BigInt,timeoutMs: null == timeoutMs ? _self.timeoutMs : timeoutMs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeHistoryWaitIntent_Timer extends BridgeHistoryWaitIntent {
  const BridgeHistoryWaitIntent_Timer({required this.durationMs}): super._();


 final  BigInt durationMs;

/// Create a copy of BridgeHistoryWaitIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeHistoryWaitIntent_TimerCopyWith<BridgeHistoryWaitIntent_Timer> get copyWith => _$BridgeHistoryWaitIntent_TimerCopyWithImpl<BridgeHistoryWaitIntent_Timer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeHistoryWaitIntent_Timer&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,durationMs);
}

@override
String toString() {
    return 'BridgeHistoryWaitIntent.timer(durationMs: $durationMs)';
}


}

/// @nodoc
abstract mixin class $BridgeHistoryWaitIntent_TimerCopyWith<$Res> implements $BridgeHistoryWaitIntentCopyWith<$Res> {
  factory $BridgeHistoryWaitIntent_TimerCopyWith(BridgeHistoryWaitIntent_Timer value, $Res Function(BridgeHistoryWaitIntent_Timer) _then) = _$BridgeHistoryWaitIntent_TimerCopyWithImpl;
@useResult
$Res call({
 BigInt durationMs
});




}
/// @nodoc
class _$BridgeHistoryWaitIntent_TimerCopyWithImpl<$Res>
    implements $BridgeHistoryWaitIntent_TimerCopyWith<$Res> {
  _$BridgeHistoryWaitIntent_TimerCopyWithImpl(this._self, this._then);

  final BridgeHistoryWaitIntent_Timer _self;
  final $Res Function(BridgeHistoryWaitIntent_Timer) _then;

/// Create a copy of BridgeHistoryWaitIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? durationMs = null,}) {
  return _then(BridgeHistoryWaitIntent_Timer(
durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
