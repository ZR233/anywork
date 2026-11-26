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
mixin _$BridgeConversationEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeConversationEvent()';
}


}

/// @nodoc
class $BridgeConversationEventCopyWith<$Res>  {
$BridgeConversationEventCopyWith(BridgeConversationEvent _, $Res Function(BridgeConversationEvent) __);
}


/// Adds pattern-matching-related methods to [BridgeConversationEvent].
extension BridgeConversationEventPatterns on BridgeConversationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeConversationEvent_Timeline value)?  timeline,TResult Function( BridgeConversationEvent_LiveStatus value)?  liveStatus,TResult Function( BridgeConversationEvent_SessionMeta value)?  sessionMeta,TResult Function( BridgeConversationEvent_InputPresented value)?  inputPresented,TResult Function( BridgeConversationEvent_ResyncRequired value)?  resyncRequired,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeConversationEvent_Timeline() when timeline != null:
return timeline(_that);case BridgeConversationEvent_LiveStatus() when liveStatus != null:
return liveStatus(_that);case BridgeConversationEvent_SessionMeta() when sessionMeta != null:
return sessionMeta(_that);case BridgeConversationEvent_InputPresented() when inputPresented != null:
return inputPresented(_that);case BridgeConversationEvent_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeConversationEvent_Timeline value)  timeline,required TResult Function( BridgeConversationEvent_LiveStatus value)  liveStatus,required TResult Function( BridgeConversationEvent_SessionMeta value)  sessionMeta,required TResult Function( BridgeConversationEvent_InputPresented value)  inputPresented,required TResult Function( BridgeConversationEvent_ResyncRequired value)  resyncRequired,}){
final _that = this;
switch (_that) {
case BridgeConversationEvent_Timeline():
return timeline(_that);case BridgeConversationEvent_LiveStatus():
return liveStatus(_that);case BridgeConversationEvent_SessionMeta():
return sessionMeta(_that);case BridgeConversationEvent_InputPresented():
return inputPresented(_that);case BridgeConversationEvent_ResyncRequired():
return resyncRequired(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeConversationEvent_Timeline value)?  timeline,TResult? Function( BridgeConversationEvent_LiveStatus value)?  liveStatus,TResult? Function( BridgeConversationEvent_SessionMeta value)?  sessionMeta,TResult? Function( BridgeConversationEvent_InputPresented value)?  inputPresented,TResult? Function( BridgeConversationEvent_ResyncRequired value)?  resyncRequired,}){
final _that = this;
switch (_that) {
case BridgeConversationEvent_Timeline() when timeline != null:
return timeline(_that);case BridgeConversationEvent_LiveStatus() when liveStatus != null:
return liveStatus(_that);case BridgeConversationEvent_SessionMeta() when sessionMeta != null:
return sessionMeta(_that);case BridgeConversationEvent_InputPresented() when inputPresented != null:
return inputPresented(_that);case BridgeConversationEvent_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeTimelinePatch patch)?  timeline,TResult Function( BridgeLiveStatusSnapshot snapshot)?  liveStatus,TResult Function( BridgeSessionMetaSnapshot snapshot)?  sessionMeta,TResult Function( String inputId,  String itemId)?  inputPresented,TResult Function( String reason)?  resyncRequired,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeConversationEvent_Timeline() when timeline != null:
return timeline(_that.patch);case BridgeConversationEvent_LiveStatus() when liveStatus != null:
return liveStatus(_that.snapshot);case BridgeConversationEvent_SessionMeta() when sessionMeta != null:
return sessionMeta(_that.snapshot);case BridgeConversationEvent_InputPresented() when inputPresented != null:
return inputPresented(_that.inputId,_that.itemId);case BridgeConversationEvent_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeTimelinePatch patch)  timeline,required TResult Function( BridgeLiveStatusSnapshot snapshot)  liveStatus,required TResult Function( BridgeSessionMetaSnapshot snapshot)  sessionMeta,required TResult Function( String inputId,  String itemId)  inputPresented,required TResult Function( String reason)  resyncRequired,}) {final _that = this;
switch (_that) {
case BridgeConversationEvent_Timeline():
return timeline(_that.patch);case BridgeConversationEvent_LiveStatus():
return liveStatus(_that.snapshot);case BridgeConversationEvent_SessionMeta():
return sessionMeta(_that.snapshot);case BridgeConversationEvent_InputPresented():
return inputPresented(_that.inputId,_that.itemId);case BridgeConversationEvent_ResyncRequired():
return resyncRequired(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeTimelinePatch patch)?  timeline,TResult? Function( BridgeLiveStatusSnapshot snapshot)?  liveStatus,TResult? Function( BridgeSessionMetaSnapshot snapshot)?  sessionMeta,TResult? Function( String inputId,  String itemId)?  inputPresented,TResult? Function( String reason)?  resyncRequired,}) {final _that = this;
switch (_that) {
case BridgeConversationEvent_Timeline() when timeline != null:
return timeline(_that.patch);case BridgeConversationEvent_LiveStatus() when liveStatus != null:
return liveStatus(_that.snapshot);case BridgeConversationEvent_SessionMeta() when sessionMeta != null:
return sessionMeta(_that.snapshot);case BridgeConversationEvent_InputPresented() when inputPresented != null:
return inputPresented(_that.inputId,_that.itemId);case BridgeConversationEvent_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeConversationEvent_Timeline extends BridgeConversationEvent {
  const BridgeConversationEvent_Timeline({required this.patch}): super._();


 final  BridgeTimelinePatch patch;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_TimelineCopyWith<BridgeConversationEvent_Timeline> get copyWith => _$BridgeConversationEvent_TimelineCopyWithImpl<BridgeConversationEvent_Timeline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_Timeline&&(identical(other.patch, patch) || other.patch == patch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,patch);
}

@override
String toString() {
    return 'BridgeConversationEvent.timeline(patch: $patch)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_TimelineCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_TimelineCopyWith(BridgeConversationEvent_Timeline value, $Res Function(BridgeConversationEvent_Timeline) _then) = _$BridgeConversationEvent_TimelineCopyWithImpl;
@useResult
$Res call({
 BridgeTimelinePatch patch
});


$BridgeTimelinePatchCopyWith<$Res> get patch;

}
/// @nodoc
class _$BridgeConversationEvent_TimelineCopyWithImpl<$Res>
    implements $BridgeConversationEvent_TimelineCopyWith<$Res> {
  _$BridgeConversationEvent_TimelineCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_Timeline _self;
  final $Res Function(BridgeConversationEvent_Timeline) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? patch = null,}) {
  return _then(BridgeConversationEvent_Timeline(
patch: null == patch ? _self.patch : patch // ignore: cast_nullable_to_non_nullable
as BridgeTimelinePatch,
  ));
}

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeTimelinePatchCopyWith<$Res> get patch {

  return $BridgeTimelinePatchCopyWith<$Res>(_self.patch, (value) {
    return _then(_self.copyWith(patch: value));
  });
}
}

/// @nodoc


class BridgeConversationEvent_LiveStatus extends BridgeConversationEvent {
  const BridgeConversationEvent_LiveStatus({required this.snapshot}): super._();


 final  BridgeLiveStatusSnapshot snapshot;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_LiveStatusCopyWith<BridgeConversationEvent_LiveStatus> get copyWith => _$BridgeConversationEvent_LiveStatusCopyWithImpl<BridgeConversationEvent_LiveStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_LiveStatus&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,snapshot);
}

@override
String toString() {
    return 'BridgeConversationEvent.liveStatus(snapshot: $snapshot)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_LiveStatusCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_LiveStatusCopyWith(BridgeConversationEvent_LiveStatus value, $Res Function(BridgeConversationEvent_LiveStatus) _then) = _$BridgeConversationEvent_LiveStatusCopyWithImpl;
@useResult
$Res call({
 BridgeLiveStatusSnapshot snapshot
});




}
/// @nodoc
class _$BridgeConversationEvent_LiveStatusCopyWithImpl<$Res>
    implements $BridgeConversationEvent_LiveStatusCopyWith<$Res> {
  _$BridgeConversationEvent_LiveStatusCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_LiveStatus _self;
  final $Res Function(BridgeConversationEvent_LiveStatus) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? snapshot = null,}) {
  return _then(BridgeConversationEvent_LiveStatus(
snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as BridgeLiveStatusSnapshot,
  ));
}


}

/// @nodoc


class BridgeConversationEvent_SessionMeta extends BridgeConversationEvent {
  const BridgeConversationEvent_SessionMeta({required this.snapshot}): super._();


 final  BridgeSessionMetaSnapshot snapshot;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_SessionMetaCopyWith<BridgeConversationEvent_SessionMeta> get copyWith => _$BridgeConversationEvent_SessionMetaCopyWithImpl<BridgeConversationEvent_SessionMeta>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_SessionMeta&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,snapshot);
}

@override
String toString() {
    return 'BridgeConversationEvent.sessionMeta(snapshot: $snapshot)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_SessionMetaCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_SessionMetaCopyWith(BridgeConversationEvent_SessionMeta value, $Res Function(BridgeConversationEvent_SessionMeta) _then) = _$BridgeConversationEvent_SessionMetaCopyWithImpl;
@useResult
$Res call({
 BridgeSessionMetaSnapshot snapshot
});




}
/// @nodoc
class _$BridgeConversationEvent_SessionMetaCopyWithImpl<$Res>
    implements $BridgeConversationEvent_SessionMetaCopyWith<$Res> {
  _$BridgeConversationEvent_SessionMetaCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_SessionMeta _self;
  final $Res Function(BridgeConversationEvent_SessionMeta) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? snapshot = null,}) {
  return _then(BridgeConversationEvent_SessionMeta(
snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as BridgeSessionMetaSnapshot,
  ));
}


}

/// @nodoc


class BridgeConversationEvent_InputPresented extends BridgeConversationEvent {
  const BridgeConversationEvent_InputPresented({required this.inputId, required this.itemId}): super._();


 final  String inputId;
 final  String itemId;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_InputPresentedCopyWith<BridgeConversationEvent_InputPresented> get copyWith => _$BridgeConversationEvent_InputPresentedCopyWithImpl<BridgeConversationEvent_InputPresented>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_InputPresented&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,inputId,itemId);
}

@override
String toString() {
    return 'BridgeConversationEvent.inputPresented(inputId: $inputId, itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_InputPresentedCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_InputPresentedCopyWith(BridgeConversationEvent_InputPresented value, $Res Function(BridgeConversationEvent_InputPresented) _then) = _$BridgeConversationEvent_InputPresentedCopyWithImpl;
@useResult
$Res call({
 String inputId, String itemId
});




}
/// @nodoc
class _$BridgeConversationEvent_InputPresentedCopyWithImpl<$Res>
    implements $BridgeConversationEvent_InputPresentedCopyWith<$Res> {
  _$BridgeConversationEvent_InputPresentedCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_InputPresented _self;
  final $Res Function(BridgeConversationEvent_InputPresented) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? inputId = null,Object? itemId = null,}) {
  return _then(BridgeConversationEvent_InputPresented(
inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeConversationEvent_ResyncRequired extends BridgeConversationEvent {
  const BridgeConversationEvent_ResyncRequired({required this.reason}): super._();


 final  String reason;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_ResyncRequiredCopyWith<BridgeConversationEvent_ResyncRequired> get copyWith => _$BridgeConversationEvent_ResyncRequiredCopyWithImpl<BridgeConversationEvent_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_ResyncRequired&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'BridgeConversationEvent.resyncRequired(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_ResyncRequiredCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_ResyncRequiredCopyWith(BridgeConversationEvent_ResyncRequired value, $Res Function(BridgeConversationEvent_ResyncRequired) _then) = _$BridgeConversationEvent_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$BridgeConversationEvent_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeConversationEvent_ResyncRequiredCopyWith<$Res> {
  _$BridgeConversationEvent_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_ResyncRequired _self;
  final $Res Function(BridgeConversationEvent_ResyncRequired) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeConversationEvent_ResyncRequired(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
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
mixin _$BridgeLiveStatusPhase {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLiveStatusPhase);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeLiveStatusPhase()';
}


}

/// @nodoc
class $BridgeLiveStatusPhaseCopyWith<$Res>  {
$BridgeLiveStatusPhaseCopyWith(BridgeLiveStatusPhase _, $Res Function(BridgeLiveStatusPhase) __);
}


/// Adds pattern-matching-related methods to [BridgeLiveStatusPhase].
extension BridgeLiveStatusPhasePatterns on BridgeLiveStatusPhase {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLiveStatusPhase_Idle value)?  idle,TResult Function( BridgeLiveStatusPhase_Working value)?  working,TResult Function( BridgeLiveStatusPhase_StreamingText value)?  streamingText,TResult Function( BridgeLiveStatusPhase_Compacting value)?  compacting,TResult Function( BridgeLiveStatusPhase_Reconnecting value)?  reconnecting,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLiveStatusPhase_Idle() when idle != null:
return idle(_that);case BridgeLiveStatusPhase_Working() when working != null:
return working(_that);case BridgeLiveStatusPhase_StreamingText() when streamingText != null:
return streamingText(_that);case BridgeLiveStatusPhase_Compacting() when compacting != null:
return compacting(_that);case BridgeLiveStatusPhase_Reconnecting() when reconnecting != null:
return reconnecting(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLiveStatusPhase_Idle value)  idle,required TResult Function( BridgeLiveStatusPhase_Working value)  working,required TResult Function( BridgeLiveStatusPhase_StreamingText value)  streamingText,required TResult Function( BridgeLiveStatusPhase_Compacting value)  compacting,required TResult Function( BridgeLiveStatusPhase_Reconnecting value)  reconnecting,}){
final _that = this;
switch (_that) {
case BridgeLiveStatusPhase_Idle():
return idle(_that);case BridgeLiveStatusPhase_Working():
return working(_that);case BridgeLiveStatusPhase_StreamingText():
return streamingText(_that);case BridgeLiveStatusPhase_Compacting():
return compacting(_that);case BridgeLiveStatusPhase_Reconnecting():
return reconnecting(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLiveStatusPhase_Idle value)?  idle,TResult? Function( BridgeLiveStatusPhase_Working value)?  working,TResult? Function( BridgeLiveStatusPhase_StreamingText value)?  streamingText,TResult? Function( BridgeLiveStatusPhase_Compacting value)?  compacting,TResult? Function( BridgeLiveStatusPhase_Reconnecting value)?  reconnecting,}){
final _that = this;
switch (_that) {
case BridgeLiveStatusPhase_Idle() when idle != null:
return idle(_that);case BridgeLiveStatusPhase_Working() when working != null:
return working(_that);case BridgeLiveStatusPhase_StreamingText() when streamingText != null:
return streamingText(_that);case BridgeLiveStatusPhase_Compacting() when compacting != null:
return compacting(_that);case BridgeLiveStatusPhase_Reconnecting() when reconnecting != null:
return reconnecting(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( List<BridgeLiveWorkItem> items,  String? reasoningPreview,  PlatformInt64? startedAtMs)?  working,TResult Function( String attemptId,  String itemId,  String text,  PlatformInt64? startedAtMs)?  streamingText,TResult Function( bool manual,  PlatformInt64? startedAtMs)?  compacting,TResult Function( String attemptId,  String message,  BigInt? retryAfterMs,  int attempt)?  reconnecting,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLiveStatusPhase_Idle() when idle != null:
return idle();case BridgeLiveStatusPhase_Working() when working != null:
return working(_that.items,_that.reasoningPreview,_that.startedAtMs);case BridgeLiveStatusPhase_StreamingText() when streamingText != null:
return streamingText(_that.attemptId,_that.itemId,_that.text,_that.startedAtMs);case BridgeLiveStatusPhase_Compacting() when compacting != null:
return compacting(_that.manual,_that.startedAtMs);case BridgeLiveStatusPhase_Reconnecting() when reconnecting != null:
return reconnecting(_that.attemptId,_that.message,_that.retryAfterMs,_that.attempt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( List<BridgeLiveWorkItem> items,  String? reasoningPreview,  PlatformInt64? startedAtMs)  working,required TResult Function( String attemptId,  String itemId,  String text,  PlatformInt64? startedAtMs)  streamingText,required TResult Function( bool manual,  PlatformInt64? startedAtMs)  compacting,required TResult Function( String attemptId,  String message,  BigInt? retryAfterMs,  int attempt)  reconnecting,}) {final _that = this;
switch (_that) {
case BridgeLiveStatusPhase_Idle():
return idle();case BridgeLiveStatusPhase_Working():
return working(_that.items,_that.reasoningPreview,_that.startedAtMs);case BridgeLiveStatusPhase_StreamingText():
return streamingText(_that.attemptId,_that.itemId,_that.text,_that.startedAtMs);case BridgeLiveStatusPhase_Compacting():
return compacting(_that.manual,_that.startedAtMs);case BridgeLiveStatusPhase_Reconnecting():
return reconnecting(_that.attemptId,_that.message,_that.retryAfterMs,_that.attempt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( List<BridgeLiveWorkItem> items,  String? reasoningPreview,  PlatformInt64? startedAtMs)?  working,TResult? Function( String attemptId,  String itemId,  String text,  PlatformInt64? startedAtMs)?  streamingText,TResult? Function( bool manual,  PlatformInt64? startedAtMs)?  compacting,TResult? Function( String attemptId,  String message,  BigInt? retryAfterMs,  int attempt)?  reconnecting,}) {final _that = this;
switch (_that) {
case BridgeLiveStatusPhase_Idle() when idle != null:
return idle();case BridgeLiveStatusPhase_Working() when working != null:
return working(_that.items,_that.reasoningPreview,_that.startedAtMs);case BridgeLiveStatusPhase_StreamingText() when streamingText != null:
return streamingText(_that.attemptId,_that.itemId,_that.text,_that.startedAtMs);case BridgeLiveStatusPhase_Compacting() when compacting != null:
return compacting(_that.manual,_that.startedAtMs);case BridgeLiveStatusPhase_Reconnecting() when reconnecting != null:
return reconnecting(_that.attemptId,_that.message,_that.retryAfterMs,_that.attempt);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLiveStatusPhase_Idle extends BridgeLiveStatusPhase {
  const BridgeLiveStatusPhase_Idle(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLiveStatusPhase_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeLiveStatusPhase.idle()';
}


}




/// @nodoc


class BridgeLiveStatusPhase_Working extends BridgeLiveStatusPhase {
  const BridgeLiveStatusPhase_Working({required  List<BridgeLiveWorkItem> items, this.reasoningPreview, this.startedAtMs}): _items = items,super._();


 final  List<BridgeLiveWorkItem> _items;
 List<BridgeLiveWorkItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

 final  String? reasoningPreview;
 final  PlatformInt64? startedAtMs;

/// Create a copy of BridgeLiveStatusPhase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLiveStatusPhase_WorkingCopyWith<BridgeLiveStatusPhase_Working> get copyWith => _$BridgeLiveStatusPhase_WorkingCopyWithImpl<BridgeLiveStatusPhase_Working>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLiveStatusPhase_Working&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.reasoningPreview, reasoningPreview) || other.reasoningPreview == reasoningPreview)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),reasoningPreview,startedAtMs);
}

@override
String toString() {
    return 'BridgeLiveStatusPhase.working(items: $items, reasoningPreview: $reasoningPreview, startedAtMs: $startedAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeLiveStatusPhase_WorkingCopyWith<$Res> implements $BridgeLiveStatusPhaseCopyWith<$Res> {
  factory $BridgeLiveStatusPhase_WorkingCopyWith(BridgeLiveStatusPhase_Working value, $Res Function(BridgeLiveStatusPhase_Working) _then) = _$BridgeLiveStatusPhase_WorkingCopyWithImpl;
@useResult
$Res call({
 List<BridgeLiveWorkItem> items, String? reasoningPreview, PlatformInt64? startedAtMs
});




}
/// @nodoc
class _$BridgeLiveStatusPhase_WorkingCopyWithImpl<$Res>
    implements $BridgeLiveStatusPhase_WorkingCopyWith<$Res> {
  _$BridgeLiveStatusPhase_WorkingCopyWithImpl(this._self, this._then);

  final BridgeLiveStatusPhase_Working _self;
  final $Res Function(BridgeLiveStatusPhase_Working) _then;

/// Create a copy of BridgeLiveStatusPhase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? items = null,Object? reasoningPreview = freezed,Object? startedAtMs = freezed,}) {
  return _then(BridgeLiveStatusPhase_Working(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<BridgeLiveWorkItem>,reasoningPreview: freezed == reasoningPreview ? _self.reasoningPreview : reasoningPreview // ignore: cast_nullable_to_non_nullable
as String?,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeLiveStatusPhase_StreamingText extends BridgeLiveStatusPhase {
  const BridgeLiveStatusPhase_StreamingText({required this.attemptId, required this.itemId, required this.text, this.startedAtMs}): super._();


 final  String attemptId;
 final  String itemId;
 final  String text;
 final  PlatformInt64? startedAtMs;

/// Create a copy of BridgeLiveStatusPhase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLiveStatusPhase_StreamingTextCopyWith<BridgeLiveStatusPhase_StreamingText> get copyWith => _$BridgeLiveStatusPhase_StreamingTextCopyWithImpl<BridgeLiveStatusPhase_StreamingText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLiveStatusPhase_StreamingText&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.text, text) || other.text == text)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,itemId,text,startedAtMs);
}

@override
String toString() {
    return 'BridgeLiveStatusPhase.streamingText(attemptId: $attemptId, itemId: $itemId, text: $text, startedAtMs: $startedAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeLiveStatusPhase_StreamingTextCopyWith<$Res> implements $BridgeLiveStatusPhaseCopyWith<$Res> {
  factory $BridgeLiveStatusPhase_StreamingTextCopyWith(BridgeLiveStatusPhase_StreamingText value, $Res Function(BridgeLiveStatusPhase_StreamingText) _then) = _$BridgeLiveStatusPhase_StreamingTextCopyWithImpl;
@useResult
$Res call({
 String attemptId, String itemId, String text, PlatformInt64? startedAtMs
});




}
/// @nodoc
class _$BridgeLiveStatusPhase_StreamingTextCopyWithImpl<$Res>
    implements $BridgeLiveStatusPhase_StreamingTextCopyWith<$Res> {
  _$BridgeLiveStatusPhase_StreamingTextCopyWithImpl(this._self, this._then);

  final BridgeLiveStatusPhase_StreamingText _self;
  final $Res Function(BridgeLiveStatusPhase_StreamingText) _then;

/// Create a copy of BridgeLiveStatusPhase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? itemId = null,Object? text = null,Object? startedAtMs = freezed,}) {
  return _then(BridgeLiveStatusPhase_StreamingText(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeLiveStatusPhase_Compacting extends BridgeLiveStatusPhase {
  const BridgeLiveStatusPhase_Compacting({required this.manual, this.startedAtMs}): super._();


 final  bool manual;
 final  PlatformInt64? startedAtMs;

/// Create a copy of BridgeLiveStatusPhase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLiveStatusPhase_CompactingCopyWith<BridgeLiveStatusPhase_Compacting> get copyWith => _$BridgeLiveStatusPhase_CompactingCopyWithImpl<BridgeLiveStatusPhase_Compacting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLiveStatusPhase_Compacting&&(identical(other.manual, manual) || other.manual == manual)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,manual,startedAtMs);
}

@override
String toString() {
    return 'BridgeLiveStatusPhase.compacting(manual: $manual, startedAtMs: $startedAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeLiveStatusPhase_CompactingCopyWith<$Res> implements $BridgeLiveStatusPhaseCopyWith<$Res> {
  factory $BridgeLiveStatusPhase_CompactingCopyWith(BridgeLiveStatusPhase_Compacting value, $Res Function(BridgeLiveStatusPhase_Compacting) _then) = _$BridgeLiveStatusPhase_CompactingCopyWithImpl;
@useResult
$Res call({
 bool manual, PlatformInt64? startedAtMs
});




}
/// @nodoc
class _$BridgeLiveStatusPhase_CompactingCopyWithImpl<$Res>
    implements $BridgeLiveStatusPhase_CompactingCopyWith<$Res> {
  _$BridgeLiveStatusPhase_CompactingCopyWithImpl(this._self, this._then);

  final BridgeLiveStatusPhase_Compacting _self;
  final $Res Function(BridgeLiveStatusPhase_Compacting) _then;

/// Create a copy of BridgeLiveStatusPhase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? manual = null,Object? startedAtMs = freezed,}) {
  return _then(BridgeLiveStatusPhase_Compacting(
manual: null == manual ? _self.manual : manual // ignore: cast_nullable_to_non_nullable
as bool,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeLiveStatusPhase_Reconnecting extends BridgeLiveStatusPhase {
  const BridgeLiveStatusPhase_Reconnecting({required this.attemptId, required this.message, this.retryAfterMs, required this.attempt}): super._();


 final  String attemptId;
 final  String message;
 final  BigInt? retryAfterMs;
 final  int attempt;

/// Create a copy of BridgeLiveStatusPhase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLiveStatusPhase_ReconnectingCopyWith<BridgeLiveStatusPhase_Reconnecting> get copyWith => _$BridgeLiveStatusPhase_ReconnectingCopyWithImpl<BridgeLiveStatusPhase_Reconnecting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLiveStatusPhase_Reconnecting&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryAfterMs, retryAfterMs) || other.retryAfterMs == retryAfterMs)&&(identical(other.attempt, attempt) || other.attempt == attempt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,message,retryAfterMs,attempt);
}

@override
String toString() {
    return 'BridgeLiveStatusPhase.reconnecting(attemptId: $attemptId, message: $message, retryAfterMs: $retryAfterMs, attempt: $attempt)';
}


}

/// @nodoc
abstract mixin class $BridgeLiveStatusPhase_ReconnectingCopyWith<$Res> implements $BridgeLiveStatusPhaseCopyWith<$Res> {
  factory $BridgeLiveStatusPhase_ReconnectingCopyWith(BridgeLiveStatusPhase_Reconnecting value, $Res Function(BridgeLiveStatusPhase_Reconnecting) _then) = _$BridgeLiveStatusPhase_ReconnectingCopyWithImpl;
@useResult
$Res call({
 String attemptId, String message, BigInt? retryAfterMs, int attempt
});




}
/// @nodoc
class _$BridgeLiveStatusPhase_ReconnectingCopyWithImpl<$Res>
    implements $BridgeLiveStatusPhase_ReconnectingCopyWith<$Res> {
  _$BridgeLiveStatusPhase_ReconnectingCopyWithImpl(this._self, this._then);

  final BridgeLiveStatusPhase_Reconnecting _self;
  final $Res Function(BridgeLiveStatusPhase_Reconnecting) _then;

/// Create a copy of BridgeLiveStatusPhase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? message = null,Object? retryAfterMs = freezed,Object? attempt = null,}) {
  return _then(BridgeLiveStatusPhase_Reconnecting(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryAfterMs: freezed == retryAfterMs ? _self.retryAfterMs : retryAfterMs // ignore: cast_nullable_to_non_nullable
as BigInt?,attempt: null == attempt ? _self.attempt : attempt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineItem {

 String get id;
/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItemCopyWith<BridgeTimelineItem> get copyWith => _$BridgeTimelineItemCopyWithImpl<BridgeTimelineItem>(this as BridgeTimelineItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeTimelineItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem&&(identical(other.id, _this.id) || other.id == _this.id));
}


@override
int get hashCode {
  final _this = this as BridgeTimelineItem;
  return Object.hash(runtimeType,_this.id);
}

@override
String toString() {
  final _this = this as BridgeTimelineItem;
  return 'BridgeTimelineItem(id: ${_this.id})';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItemCopyWith<$Res>  {
  factory $BridgeTimelineItemCopyWith(BridgeTimelineItem value, $Res Function(BridgeTimelineItem) _then) = _$BridgeTimelineItemCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BridgeTimelineItemCopyWithImpl<$Res>
    implements $BridgeTimelineItemCopyWith<$Res> {
  _$BridgeTimelineItemCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem _self;
  final $Res Function(BridgeTimelineItem) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeTimelineItem].
extension BridgeTimelineItemPatterns on BridgeTimelineItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineItem_UserMessage value)?  userMessage,TResult Function( BridgeTimelineItem_AssistantText value)?  assistantText,TResult Function( BridgeTimelineItem_WorkGroup value)?  workGroup,TResult Function( BridgeTimelineItem_Compaction value)?  compaction,TResult Function( BridgeTimelineItem_PlanResolution value)?  planResolution,TResult Function( BridgeTimelineItem_ConnectionNotice value)?  connectionNotice,TResult Function( BridgeTimelineItem_TurnOutcome value)?  turnOutcome,TResult Function( BridgeTimelineItem_StandaloneTool value)?  standaloneTool,TResult Function( BridgeTimelineItem_Fallback value)?  fallback,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineItem_UserMessage() when userMessage != null:
return userMessage(_that);case BridgeTimelineItem_AssistantText() when assistantText != null:
return assistantText(_that);case BridgeTimelineItem_WorkGroup() when workGroup != null:
return workGroup(_that);case BridgeTimelineItem_Compaction() when compaction != null:
return compaction(_that);case BridgeTimelineItem_PlanResolution() when planResolution != null:
return planResolution(_that);case BridgeTimelineItem_ConnectionNotice() when connectionNotice != null:
return connectionNotice(_that);case BridgeTimelineItem_TurnOutcome() when turnOutcome != null:
return turnOutcome(_that);case BridgeTimelineItem_StandaloneTool() when standaloneTool != null:
return standaloneTool(_that);case BridgeTimelineItem_Fallback() when fallback != null:
return fallback(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineItem_UserMessage value)  userMessage,required TResult Function( BridgeTimelineItem_AssistantText value)  assistantText,required TResult Function( BridgeTimelineItem_WorkGroup value)  workGroup,required TResult Function( BridgeTimelineItem_Compaction value)  compaction,required TResult Function( BridgeTimelineItem_PlanResolution value)  planResolution,required TResult Function( BridgeTimelineItem_ConnectionNotice value)  connectionNotice,required TResult Function( BridgeTimelineItem_TurnOutcome value)  turnOutcome,required TResult Function( BridgeTimelineItem_StandaloneTool value)  standaloneTool,required TResult Function( BridgeTimelineItem_Fallback value)  fallback,}){
final _that = this;
switch (_that) {
case BridgeTimelineItem_UserMessage():
return userMessage(_that);case BridgeTimelineItem_AssistantText():
return assistantText(_that);case BridgeTimelineItem_WorkGroup():
return workGroup(_that);case BridgeTimelineItem_Compaction():
return compaction(_that);case BridgeTimelineItem_PlanResolution():
return planResolution(_that);case BridgeTimelineItem_ConnectionNotice():
return connectionNotice(_that);case BridgeTimelineItem_TurnOutcome():
return turnOutcome(_that);case BridgeTimelineItem_StandaloneTool():
return standaloneTool(_that);case BridgeTimelineItem_Fallback():
return fallback(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineItem_UserMessage value)?  userMessage,TResult? Function( BridgeTimelineItem_AssistantText value)?  assistantText,TResult? Function( BridgeTimelineItem_WorkGroup value)?  workGroup,TResult? Function( BridgeTimelineItem_Compaction value)?  compaction,TResult? Function( BridgeTimelineItem_PlanResolution value)?  planResolution,TResult? Function( BridgeTimelineItem_ConnectionNotice value)?  connectionNotice,TResult? Function( BridgeTimelineItem_TurnOutcome value)?  turnOutcome,TResult? Function( BridgeTimelineItem_StandaloneTool value)?  standaloneTool,TResult? Function( BridgeTimelineItem_Fallback value)?  fallback,}){
final _that = this;
switch (_that) {
case BridgeTimelineItem_UserMessage() when userMessage != null:
return userMessage(_that);case BridgeTimelineItem_AssistantText() when assistantText != null:
return assistantText(_that);case BridgeTimelineItem_WorkGroup() when workGroup != null:
return workGroup(_that);case BridgeTimelineItem_Compaction() when compaction != null:
return compaction(_that);case BridgeTimelineItem_PlanResolution() when planResolution != null:
return planResolution(_that);case BridgeTimelineItem_ConnectionNotice() when connectionNotice != null:
return connectionNotice(_that);case BridgeTimelineItem_TurnOutcome() when turnOutcome != null:
return turnOutcome(_that);case BridgeTimelineItem_StandaloneTool() when standaloneTool != null:
return standaloneTool(_that);case BridgeTimelineItem_Fallback() when fallback != null:
return fallback(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  BigInt seq,  String? turnId,  String? inputId,  String channel,  String text,  String attachmentsJson,  PlatformInt64? occurredAtMs)?  userMessage,TResult Function( String id,  BigInt seq,  String? turnId,  String? attemptId,  String channel,  String text,  BridgeBodyRef? bodyRef,  bool isFinalTurnDelivery,  String outcome,  BridgeModelRecoveryNotice? modelRecovery,  PlatformInt64? occurredAtMs)?  assistantText,TResult Function( String id,  BigInt firstSeq,  BigInt lastSeq,  BigInt? afterBoundarySeq,  BigInt? beforeBoundarySeq,  int memberCount,  String summary,  BridgeWorkGroupStatus status,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)?  workGroup,TResult Function( String id,  BigInt seq,  String? turnId,  String summary,  String outcome,  BigInt? tokensBefore,  BigInt? tokensAfter,  PlatformInt64? occurredAtMs)?  compaction,TResult Function( String id,  BigInt seq,  String? turnId,  String decision,  String? document,  BridgeBodyRef? documentRef,  String? feedback,  PlatformInt64? occurredAtMs)?  planResolution,TResult Function( String id,  BigInt seq,  String? turnId,  String scope,  String state,  String transport,  String? fallbackTransport,  int attempt,  int maxAttempts,  bool recoverable,  String? reason,  BigInt? durationMs,  PlatformInt64? occurredAtMs)?  connectionNotice,TResult Function( String id,  BigInt seq,  String? turnId,  String? inputId,  String outcome,  String? message,  BridgeTurnFailureDto? turnFailure,  PlatformInt64? occurredAtMs)?  turnOutcome,TResult Function( String id,  BigInt seq,  String? turnId,  String callId,  String toolName,  String? presentationContract,  String state,  String summary,  String payloadJson,  List<BridgeBodyRef> bodies,  PlatformInt64? occurredAtMs)?  standaloneTool,TResult Function( String id,  BigInt seq,  String eventId,  String eventKind,  String reason,  String? rawPreview,  PlatformInt64? occurredAtMs)?  fallback,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineItem_UserMessage() when userMessage != null:
return userMessage(_that.id,_that.seq,_that.turnId,_that.inputId,_that.channel,_that.text,_that.attachmentsJson,_that.occurredAtMs);case BridgeTimelineItem_AssistantText() when assistantText != null:
return assistantText(_that.id,_that.seq,_that.turnId,_that.attemptId,_that.channel,_that.text,_that.bodyRef,_that.isFinalTurnDelivery,_that.outcome,_that.modelRecovery,_that.occurredAtMs);case BridgeTimelineItem_WorkGroup() when workGroup != null:
return workGroup(_that.id,_that.firstSeq,_that.lastSeq,_that.afterBoundarySeq,_that.beforeBoundarySeq,_that.memberCount,_that.summary,_that.status,_that.startedAtMs,_that.finishedAtMs);case BridgeTimelineItem_Compaction() when compaction != null:
return compaction(_that.id,_that.seq,_that.turnId,_that.summary,_that.outcome,_that.tokensBefore,_that.tokensAfter,_that.occurredAtMs);case BridgeTimelineItem_PlanResolution() when planResolution != null:
return planResolution(_that.id,_that.seq,_that.turnId,_that.decision,_that.document,_that.documentRef,_that.feedback,_that.occurredAtMs);case BridgeTimelineItem_ConnectionNotice() when connectionNotice != null:
return connectionNotice(_that.id,_that.seq,_that.turnId,_that.scope,_that.state,_that.transport,_that.fallbackTransport,_that.attempt,_that.maxAttempts,_that.recoverable,_that.reason,_that.durationMs,_that.occurredAtMs);case BridgeTimelineItem_TurnOutcome() when turnOutcome != null:
return turnOutcome(_that.id,_that.seq,_that.turnId,_that.inputId,_that.outcome,_that.message,_that.turnFailure,_that.occurredAtMs);case BridgeTimelineItem_StandaloneTool() when standaloneTool != null:
return standaloneTool(_that.id,_that.seq,_that.turnId,_that.callId,_that.toolName,_that.presentationContract,_that.state,_that.summary,_that.payloadJson,_that.bodies,_that.occurredAtMs);case BridgeTimelineItem_Fallback() when fallback != null:
return fallback(_that.id,_that.seq,_that.eventId,_that.eventKind,_that.reason,_that.rawPreview,_that.occurredAtMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  BigInt seq,  String? turnId,  String? inputId,  String channel,  String text,  String attachmentsJson,  PlatformInt64? occurredAtMs)  userMessage,required TResult Function( String id,  BigInt seq,  String? turnId,  String? attemptId,  String channel,  String text,  BridgeBodyRef? bodyRef,  bool isFinalTurnDelivery,  String outcome,  BridgeModelRecoveryNotice? modelRecovery,  PlatformInt64? occurredAtMs)  assistantText,required TResult Function( String id,  BigInt firstSeq,  BigInt lastSeq,  BigInt? afterBoundarySeq,  BigInt? beforeBoundarySeq,  int memberCount,  String summary,  BridgeWorkGroupStatus status,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)  workGroup,required TResult Function( String id,  BigInt seq,  String? turnId,  String summary,  String outcome,  BigInt? tokensBefore,  BigInt? tokensAfter,  PlatformInt64? occurredAtMs)  compaction,required TResult Function( String id,  BigInt seq,  String? turnId,  String decision,  String? document,  BridgeBodyRef? documentRef,  String? feedback,  PlatformInt64? occurredAtMs)  planResolution,required TResult Function( String id,  BigInt seq,  String? turnId,  String scope,  String state,  String transport,  String? fallbackTransport,  int attempt,  int maxAttempts,  bool recoverable,  String? reason,  BigInt? durationMs,  PlatformInt64? occurredAtMs)  connectionNotice,required TResult Function( String id,  BigInt seq,  String? turnId,  String? inputId,  String outcome,  String? message,  BridgeTurnFailureDto? turnFailure,  PlatformInt64? occurredAtMs)  turnOutcome,required TResult Function( String id,  BigInt seq,  String? turnId,  String callId,  String toolName,  String? presentationContract,  String state,  String summary,  String payloadJson,  List<BridgeBodyRef> bodies,  PlatformInt64? occurredAtMs)  standaloneTool,required TResult Function( String id,  BigInt seq,  String eventId,  String eventKind,  String reason,  String? rawPreview,  PlatformInt64? occurredAtMs)  fallback,}) {final _that = this;
switch (_that) {
case BridgeTimelineItem_UserMessage():
return userMessage(_that.id,_that.seq,_that.turnId,_that.inputId,_that.channel,_that.text,_that.attachmentsJson,_that.occurredAtMs);case BridgeTimelineItem_AssistantText():
return assistantText(_that.id,_that.seq,_that.turnId,_that.attemptId,_that.channel,_that.text,_that.bodyRef,_that.isFinalTurnDelivery,_that.outcome,_that.modelRecovery,_that.occurredAtMs);case BridgeTimelineItem_WorkGroup():
return workGroup(_that.id,_that.firstSeq,_that.lastSeq,_that.afterBoundarySeq,_that.beforeBoundarySeq,_that.memberCount,_that.summary,_that.status,_that.startedAtMs,_that.finishedAtMs);case BridgeTimelineItem_Compaction():
return compaction(_that.id,_that.seq,_that.turnId,_that.summary,_that.outcome,_that.tokensBefore,_that.tokensAfter,_that.occurredAtMs);case BridgeTimelineItem_PlanResolution():
return planResolution(_that.id,_that.seq,_that.turnId,_that.decision,_that.document,_that.documentRef,_that.feedback,_that.occurredAtMs);case BridgeTimelineItem_ConnectionNotice():
return connectionNotice(_that.id,_that.seq,_that.turnId,_that.scope,_that.state,_that.transport,_that.fallbackTransport,_that.attempt,_that.maxAttempts,_that.recoverable,_that.reason,_that.durationMs,_that.occurredAtMs);case BridgeTimelineItem_TurnOutcome():
return turnOutcome(_that.id,_that.seq,_that.turnId,_that.inputId,_that.outcome,_that.message,_that.turnFailure,_that.occurredAtMs);case BridgeTimelineItem_StandaloneTool():
return standaloneTool(_that.id,_that.seq,_that.turnId,_that.callId,_that.toolName,_that.presentationContract,_that.state,_that.summary,_that.payloadJson,_that.bodies,_that.occurredAtMs);case BridgeTimelineItem_Fallback():
return fallback(_that.id,_that.seq,_that.eventId,_that.eventKind,_that.reason,_that.rawPreview,_that.occurredAtMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  BigInt seq,  String? turnId,  String? inputId,  String channel,  String text,  String attachmentsJson,  PlatformInt64? occurredAtMs)?  userMessage,TResult? Function( String id,  BigInt seq,  String? turnId,  String? attemptId,  String channel,  String text,  BridgeBodyRef? bodyRef,  bool isFinalTurnDelivery,  String outcome,  BridgeModelRecoveryNotice? modelRecovery,  PlatformInt64? occurredAtMs)?  assistantText,TResult? Function( String id,  BigInt firstSeq,  BigInt lastSeq,  BigInt? afterBoundarySeq,  BigInt? beforeBoundarySeq,  int memberCount,  String summary,  BridgeWorkGroupStatus status,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)?  workGroup,TResult? Function( String id,  BigInt seq,  String? turnId,  String summary,  String outcome,  BigInt? tokensBefore,  BigInt? tokensAfter,  PlatformInt64? occurredAtMs)?  compaction,TResult? Function( String id,  BigInt seq,  String? turnId,  String decision,  String? document,  BridgeBodyRef? documentRef,  String? feedback,  PlatformInt64? occurredAtMs)?  planResolution,TResult? Function( String id,  BigInt seq,  String? turnId,  String scope,  String state,  String transport,  String? fallbackTransport,  int attempt,  int maxAttempts,  bool recoverable,  String? reason,  BigInt? durationMs,  PlatformInt64? occurredAtMs)?  connectionNotice,TResult? Function( String id,  BigInt seq,  String? turnId,  String? inputId,  String outcome,  String? message,  BridgeTurnFailureDto? turnFailure,  PlatformInt64? occurredAtMs)?  turnOutcome,TResult? Function( String id,  BigInt seq,  String? turnId,  String callId,  String toolName,  String? presentationContract,  String state,  String summary,  String payloadJson,  List<BridgeBodyRef> bodies,  PlatformInt64? occurredAtMs)?  standaloneTool,TResult? Function( String id,  BigInt seq,  String eventId,  String eventKind,  String reason,  String? rawPreview,  PlatformInt64? occurredAtMs)?  fallback,}) {final _that = this;
switch (_that) {
case BridgeTimelineItem_UserMessage() when userMessage != null:
return userMessage(_that.id,_that.seq,_that.turnId,_that.inputId,_that.channel,_that.text,_that.attachmentsJson,_that.occurredAtMs);case BridgeTimelineItem_AssistantText() when assistantText != null:
return assistantText(_that.id,_that.seq,_that.turnId,_that.attemptId,_that.channel,_that.text,_that.bodyRef,_that.isFinalTurnDelivery,_that.outcome,_that.modelRecovery,_that.occurredAtMs);case BridgeTimelineItem_WorkGroup() when workGroup != null:
return workGroup(_that.id,_that.firstSeq,_that.lastSeq,_that.afterBoundarySeq,_that.beforeBoundarySeq,_that.memberCount,_that.summary,_that.status,_that.startedAtMs,_that.finishedAtMs);case BridgeTimelineItem_Compaction() when compaction != null:
return compaction(_that.id,_that.seq,_that.turnId,_that.summary,_that.outcome,_that.tokensBefore,_that.tokensAfter,_that.occurredAtMs);case BridgeTimelineItem_PlanResolution() when planResolution != null:
return planResolution(_that.id,_that.seq,_that.turnId,_that.decision,_that.document,_that.documentRef,_that.feedback,_that.occurredAtMs);case BridgeTimelineItem_ConnectionNotice() when connectionNotice != null:
return connectionNotice(_that.id,_that.seq,_that.turnId,_that.scope,_that.state,_that.transport,_that.fallbackTransport,_that.attempt,_that.maxAttempts,_that.recoverable,_that.reason,_that.durationMs,_that.occurredAtMs);case BridgeTimelineItem_TurnOutcome() when turnOutcome != null:
return turnOutcome(_that.id,_that.seq,_that.turnId,_that.inputId,_that.outcome,_that.message,_that.turnFailure,_that.occurredAtMs);case BridgeTimelineItem_StandaloneTool() when standaloneTool != null:
return standaloneTool(_that.id,_that.seq,_that.turnId,_that.callId,_that.toolName,_that.presentationContract,_that.state,_that.summary,_that.payloadJson,_that.bodies,_that.occurredAtMs);case BridgeTimelineItem_Fallback() when fallback != null:
return fallback(_that.id,_that.seq,_that.eventId,_that.eventKind,_that.reason,_that.rawPreview,_that.occurredAtMs);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineItem_UserMessage extends BridgeTimelineItem {
  const BridgeTimelineItem_UserMessage({required this.id, required this.seq, this.turnId, this.inputId, required this.channel, required this.text, required this.attachmentsJson, this.occurredAtMs}): super._();


@override final  String id;
 final  BigInt seq;
 final  String? turnId;
 final  String? inputId;
 final  String channel;
 final  String text;
 final  String attachmentsJson;
 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItem_UserMessageCopyWith<BridgeTimelineItem_UserMessage> get copyWith => _$BridgeTimelineItem_UserMessageCopyWithImpl<BridgeTimelineItem_UserMessage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem_UserMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.channel, channel) || other.channel == channel)&&(identical(other.text, text) || other.text == text)&&(identical(other.attachmentsJson, attachmentsJson) || other.attachmentsJson == attachmentsJson)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,turnId,inputId,channel,text,attachmentsJson,occurredAtMs);
}

@override
String toString() {
    return 'BridgeTimelineItem.userMessage(id: $id, seq: $seq, turnId: $turnId, inputId: $inputId, channel: $channel, text: $text, attachmentsJson: $attachmentsJson, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItem_UserMessageCopyWith<$Res> implements $BridgeTimelineItemCopyWith<$Res> {
  factory $BridgeTimelineItem_UserMessageCopyWith(BridgeTimelineItem_UserMessage value, $Res Function(BridgeTimelineItem_UserMessage) _then) = _$BridgeTimelineItem_UserMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String? turnId, String? inputId, String channel, String text, String attachmentsJson, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeTimelineItem_UserMessageCopyWithImpl<$Res>
    implements $BridgeTimelineItem_UserMessageCopyWith<$Res> {
  _$BridgeTimelineItem_UserMessageCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem_UserMessage _self;
  final $Res Function(BridgeTimelineItem_UserMessage) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? turnId = freezed,Object? inputId = freezed,Object? channel = null,Object? text = null,Object? attachmentsJson = null,Object? occurredAtMs = freezed,}) {
  return _then(BridgeTimelineItem_UserMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String?,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,attachmentsJson: null == attachmentsJson ? _self.attachmentsJson : attachmentsJson // ignore: cast_nullable_to_non_nullable
as String,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeTimelineItem_AssistantText extends BridgeTimelineItem {
  const BridgeTimelineItem_AssistantText({required this.id, required this.seq, this.turnId, this.attemptId, required this.channel, required this.text, this.bodyRef, required this.isFinalTurnDelivery, required this.outcome, this.modelRecovery, this.occurredAtMs}): super._();


@override final  String id;
 final  BigInt seq;
 final  String? turnId;
 final  String? attemptId;
 final  String channel;
 final  String text;
 final  BridgeBodyRef? bodyRef;
 final  bool isFinalTurnDelivery;
 final  String outcome;
 final  BridgeModelRecoveryNotice? modelRecovery;
 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItem_AssistantTextCopyWith<BridgeTimelineItem_AssistantText> get copyWith => _$BridgeTimelineItem_AssistantTextCopyWithImpl<BridgeTimelineItem_AssistantText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem_AssistantText&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.channel, channel) || other.channel == channel)&&(identical(other.text, text) || other.text == text)&&(identical(other.bodyRef, bodyRef) || other.bodyRef == bodyRef)&&(identical(other.isFinalTurnDelivery, isFinalTurnDelivery) || other.isFinalTurnDelivery == isFinalTurnDelivery)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.modelRecovery, modelRecovery) || other.modelRecovery == modelRecovery)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,turnId,attemptId,channel,text,bodyRef,isFinalTurnDelivery,outcome,modelRecovery,occurredAtMs);
}

@override
String toString() {
    return 'BridgeTimelineItem.assistantText(id: $id, seq: $seq, turnId: $turnId, attemptId: $attemptId, channel: $channel, text: $text, bodyRef: $bodyRef, isFinalTurnDelivery: $isFinalTurnDelivery, outcome: $outcome, modelRecovery: $modelRecovery, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItem_AssistantTextCopyWith<$Res> implements $BridgeTimelineItemCopyWith<$Res> {
  factory $BridgeTimelineItem_AssistantTextCopyWith(BridgeTimelineItem_AssistantText value, $Res Function(BridgeTimelineItem_AssistantText) _then) = _$BridgeTimelineItem_AssistantTextCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String? turnId, String? attemptId, String channel, String text, BridgeBodyRef? bodyRef, bool isFinalTurnDelivery, String outcome, BridgeModelRecoveryNotice? modelRecovery, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeTimelineItem_AssistantTextCopyWithImpl<$Res>
    implements $BridgeTimelineItem_AssistantTextCopyWith<$Res> {
  _$BridgeTimelineItem_AssistantTextCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem_AssistantText _self;
  final $Res Function(BridgeTimelineItem_AssistantText) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? turnId = freezed,Object? attemptId = freezed,Object? channel = null,Object? text = null,Object? bodyRef = freezed,Object? isFinalTurnDelivery = null,Object? outcome = null,Object? modelRecovery = freezed,Object? occurredAtMs = freezed,}) {
  return _then(BridgeTimelineItem_AssistantText(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,attemptId: freezed == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String?,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,bodyRef: freezed == bodyRef ? _self.bodyRef : bodyRef // ignore: cast_nullable_to_non_nullable
as BridgeBodyRef?,isFinalTurnDelivery: null == isFinalTurnDelivery ? _self.isFinalTurnDelivery : isFinalTurnDelivery // ignore: cast_nullable_to_non_nullable
as bool,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,modelRecovery: freezed == modelRecovery ? _self.modelRecovery : modelRecovery // ignore: cast_nullable_to_non_nullable
as BridgeModelRecoveryNotice?,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeTimelineItem_WorkGroup extends BridgeTimelineItem {
  const BridgeTimelineItem_WorkGroup({required this.id, required this.firstSeq, required this.lastSeq, this.afterBoundarySeq, this.beforeBoundarySeq, required this.memberCount, required this.summary, required this.status, this.startedAtMs, this.finishedAtMs}): super._();


@override final  String id;
 final  BigInt firstSeq;
 final  BigInt lastSeq;
 final  BigInt? afterBoundarySeq;
 final  BigInt? beforeBoundarySeq;
 final  int memberCount;
 final  String summary;
 final  BridgeWorkGroupStatus status;
 final  PlatformInt64? startedAtMs;
 final  PlatformInt64? finishedAtMs;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItem_WorkGroupCopyWith<BridgeTimelineItem_WorkGroup> get copyWith => _$BridgeTimelineItem_WorkGroupCopyWithImpl<BridgeTimelineItem_WorkGroup>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem_WorkGroup&&(identical(other.id, id) || other.id == id)&&(identical(other.firstSeq, firstSeq) || other.firstSeq == firstSeq)&&(identical(other.lastSeq, lastSeq) || other.lastSeq == lastSeq)&&(identical(other.afterBoundarySeq, afterBoundarySeq) || other.afterBoundarySeq == afterBoundarySeq)&&(identical(other.beforeBoundarySeq, beforeBoundarySeq) || other.beforeBoundarySeq == beforeBoundarySeq)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.status, status) || other.status == status)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.finishedAtMs, finishedAtMs) || other.finishedAtMs == finishedAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,firstSeq,lastSeq,afterBoundarySeq,beforeBoundarySeq,memberCount,summary,status,startedAtMs,finishedAtMs);
}

@override
String toString() {
    return 'BridgeTimelineItem.workGroup(id: $id, firstSeq: $firstSeq, lastSeq: $lastSeq, afterBoundarySeq: $afterBoundarySeq, beforeBoundarySeq: $beforeBoundarySeq, memberCount: $memberCount, summary: $summary, status: $status, startedAtMs: $startedAtMs, finishedAtMs: $finishedAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItem_WorkGroupCopyWith<$Res> implements $BridgeTimelineItemCopyWith<$Res> {
  factory $BridgeTimelineItem_WorkGroupCopyWith(BridgeTimelineItem_WorkGroup value, $Res Function(BridgeTimelineItem_WorkGroup) _then) = _$BridgeTimelineItem_WorkGroupCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt firstSeq, BigInt lastSeq, BigInt? afterBoundarySeq, BigInt? beforeBoundarySeq, int memberCount, String summary, BridgeWorkGroupStatus status, PlatformInt64? startedAtMs, PlatformInt64? finishedAtMs
});




}
/// @nodoc
class _$BridgeTimelineItem_WorkGroupCopyWithImpl<$Res>
    implements $BridgeTimelineItem_WorkGroupCopyWith<$Res> {
  _$BridgeTimelineItem_WorkGroupCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem_WorkGroup _self;
  final $Res Function(BridgeTimelineItem_WorkGroup) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? firstSeq = null,Object? lastSeq = null,Object? afterBoundarySeq = freezed,Object? beforeBoundarySeq = freezed,Object? memberCount = null,Object? summary = null,Object? status = null,Object? startedAtMs = freezed,Object? finishedAtMs = freezed,}) {
  return _then(BridgeTimelineItem_WorkGroup(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,firstSeq: null == firstSeq ? _self.firstSeq : firstSeq // ignore: cast_nullable_to_non_nullable
as BigInt,lastSeq: null == lastSeq ? _self.lastSeq : lastSeq // ignore: cast_nullable_to_non_nullable
as BigInt,afterBoundarySeq: freezed == afterBoundarySeq ? _self.afterBoundarySeq : afterBoundarySeq // ignore: cast_nullable_to_non_nullable
as BigInt?,beforeBoundarySeq: freezed == beforeBoundarySeq ? _self.beforeBoundarySeq : beforeBoundarySeq // ignore: cast_nullable_to_non_nullable
as BigInt?,memberCount: null == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BridgeWorkGroupStatus,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,finishedAtMs: freezed == finishedAtMs ? _self.finishedAtMs : finishedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeTimelineItem_Compaction extends BridgeTimelineItem {
  const BridgeTimelineItem_Compaction({required this.id, required this.seq, this.turnId, required this.summary, required this.outcome, this.tokensBefore, this.tokensAfter, this.occurredAtMs}): super._();


@override final  String id;
 final  BigInt seq;
 final  String? turnId;
 final  String summary;
 final  String outcome;
 final  BigInt? tokensBefore;
 final  BigInt? tokensAfter;
 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItem_CompactionCopyWith<BridgeTimelineItem_Compaction> get copyWith => _$BridgeTimelineItem_CompactionCopyWithImpl<BridgeTimelineItem_Compaction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem_Compaction&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.tokensBefore, tokensBefore) || other.tokensBefore == tokensBefore)&&(identical(other.tokensAfter, tokensAfter) || other.tokensAfter == tokensAfter)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,turnId,summary,outcome,tokensBefore,tokensAfter,occurredAtMs);
}

@override
String toString() {
    return 'BridgeTimelineItem.compaction(id: $id, seq: $seq, turnId: $turnId, summary: $summary, outcome: $outcome, tokensBefore: $tokensBefore, tokensAfter: $tokensAfter, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItem_CompactionCopyWith<$Res> implements $BridgeTimelineItemCopyWith<$Res> {
  factory $BridgeTimelineItem_CompactionCopyWith(BridgeTimelineItem_Compaction value, $Res Function(BridgeTimelineItem_Compaction) _then) = _$BridgeTimelineItem_CompactionCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String? turnId, String summary, String outcome, BigInt? tokensBefore, BigInt? tokensAfter, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeTimelineItem_CompactionCopyWithImpl<$Res>
    implements $BridgeTimelineItem_CompactionCopyWith<$Res> {
  _$BridgeTimelineItem_CompactionCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem_Compaction _self;
  final $Res Function(BridgeTimelineItem_Compaction) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? turnId = freezed,Object? summary = null,Object? outcome = null,Object? tokensBefore = freezed,Object? tokensAfter = freezed,Object? occurredAtMs = freezed,}) {
  return _then(BridgeTimelineItem_Compaction(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,tokensBefore: freezed == tokensBefore ? _self.tokensBefore : tokensBefore // ignore: cast_nullable_to_non_nullable
as BigInt?,tokensAfter: freezed == tokensAfter ? _self.tokensAfter : tokensAfter // ignore: cast_nullable_to_non_nullable
as BigInt?,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeTimelineItem_PlanResolution extends BridgeTimelineItem {
  const BridgeTimelineItem_PlanResolution({required this.id, required this.seq, this.turnId, required this.decision, this.document, this.documentRef, this.feedback, this.occurredAtMs}): super._();


@override final  String id;
 final  BigInt seq;
 final  String? turnId;
 final  String decision;
 final  String? document;
 final  BridgeBodyRef? documentRef;
 final  String? feedback;
 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItem_PlanResolutionCopyWith<BridgeTimelineItem_PlanResolution> get copyWith => _$BridgeTimelineItem_PlanResolutionCopyWithImpl<BridgeTimelineItem_PlanResolution>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem_PlanResolution&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.decision, decision) || other.decision == decision)&&(identical(other.document, document) || other.document == document)&&(identical(other.documentRef, documentRef) || other.documentRef == documentRef)&&(identical(other.feedback, feedback) || other.feedback == feedback)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,turnId,decision,document,documentRef,feedback,occurredAtMs);
}

@override
String toString() {
    return 'BridgeTimelineItem.planResolution(id: $id, seq: $seq, turnId: $turnId, decision: $decision, document: $document, documentRef: $documentRef, feedback: $feedback, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItem_PlanResolutionCopyWith<$Res> implements $BridgeTimelineItemCopyWith<$Res> {
  factory $BridgeTimelineItem_PlanResolutionCopyWith(BridgeTimelineItem_PlanResolution value, $Res Function(BridgeTimelineItem_PlanResolution) _then) = _$BridgeTimelineItem_PlanResolutionCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String? turnId, String decision, String? document, BridgeBodyRef? documentRef, String? feedback, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeTimelineItem_PlanResolutionCopyWithImpl<$Res>
    implements $BridgeTimelineItem_PlanResolutionCopyWith<$Res> {
  _$BridgeTimelineItem_PlanResolutionCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem_PlanResolution _self;
  final $Res Function(BridgeTimelineItem_PlanResolution) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? turnId = freezed,Object? decision = null,Object? document = freezed,Object? documentRef = freezed,Object? feedback = freezed,Object? occurredAtMs = freezed,}) {
  return _then(BridgeTimelineItem_PlanResolution(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,decision: null == decision ? _self.decision : decision // ignore: cast_nullable_to_non_nullable
as String,document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as String?,documentRef: freezed == documentRef ? _self.documentRef : documentRef // ignore: cast_nullable_to_non_nullable
as BridgeBodyRef?,feedback: freezed == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as String?,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeTimelineItem_ConnectionNotice extends BridgeTimelineItem {
  const BridgeTimelineItem_ConnectionNotice({required this.id, required this.seq, this.turnId, required this.scope, required this.state, required this.transport, this.fallbackTransport, required this.attempt, required this.maxAttempts, required this.recoverable, this.reason, this.durationMs, this.occurredAtMs}): super._();


@override final  String id;
 final  BigInt seq;
 final  String? turnId;
 final  String scope;
 final  String state;
 final  String transport;
 final  String? fallbackTransport;
 final  int attempt;
 final  int maxAttempts;
 final  bool recoverable;
 final  String? reason;
 final  BigInt? durationMs;
 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItem_ConnectionNoticeCopyWith<BridgeTimelineItem_ConnectionNotice> get copyWith => _$BridgeTimelineItem_ConnectionNoticeCopyWithImpl<BridgeTimelineItem_ConnectionNotice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem_ConnectionNotice&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.state, state) || other.state == state)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.fallbackTransport, fallbackTransport) || other.fallbackTransport == fallbackTransport)&&(identical(other.attempt, attempt) || other.attempt == attempt)&&(identical(other.maxAttempts, maxAttempts) || other.maxAttempts == maxAttempts)&&(identical(other.recoverable, recoverable) || other.recoverable == recoverable)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,turnId,scope,state,transport,fallbackTransport,attempt,maxAttempts,recoverable,reason,durationMs,occurredAtMs);
}

@override
String toString() {
    return 'BridgeTimelineItem.connectionNotice(id: $id, seq: $seq, turnId: $turnId, scope: $scope, state: $state, transport: $transport, fallbackTransport: $fallbackTransport, attempt: $attempt, maxAttempts: $maxAttempts, recoverable: $recoverable, reason: $reason, durationMs: $durationMs, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItem_ConnectionNoticeCopyWith<$Res> implements $BridgeTimelineItemCopyWith<$Res> {
  factory $BridgeTimelineItem_ConnectionNoticeCopyWith(BridgeTimelineItem_ConnectionNotice value, $Res Function(BridgeTimelineItem_ConnectionNotice) _then) = _$BridgeTimelineItem_ConnectionNoticeCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String? turnId, String scope, String state, String transport, String? fallbackTransport, int attempt, int maxAttempts, bool recoverable, String? reason, BigInt? durationMs, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeTimelineItem_ConnectionNoticeCopyWithImpl<$Res>
    implements $BridgeTimelineItem_ConnectionNoticeCopyWith<$Res> {
  _$BridgeTimelineItem_ConnectionNoticeCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem_ConnectionNotice _self;
  final $Res Function(BridgeTimelineItem_ConnectionNotice) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? turnId = freezed,Object? scope = null,Object? state = null,Object? transport = null,Object? fallbackTransport = freezed,Object? attempt = null,Object? maxAttempts = null,Object? recoverable = null,Object? reason = freezed,Object? durationMs = freezed,Object? occurredAtMs = freezed,}) {
  return _then(BridgeTimelineItem_ConnectionNotice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as String,fallbackTransport: freezed == fallbackTransport ? _self.fallbackTransport : fallbackTransport // ignore: cast_nullable_to_non_nullable
as String?,attempt: null == attempt ? _self.attempt : attempt // ignore: cast_nullable_to_non_nullable
as int,maxAttempts: null == maxAttempts ? _self.maxAttempts : maxAttempts // ignore: cast_nullable_to_non_nullable
as int,recoverable: null == recoverable ? _self.recoverable : recoverable // ignore: cast_nullable_to_non_nullable
as bool,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,durationMs: freezed == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as BigInt?,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeTimelineItem_TurnOutcome extends BridgeTimelineItem {
  const BridgeTimelineItem_TurnOutcome({required this.id, required this.seq, this.turnId, this.inputId, required this.outcome, this.message, this.turnFailure, this.occurredAtMs}): super._();


@override final  String id;
 final  BigInt seq;
 final  String? turnId;
 final  String? inputId;
 final  String outcome;
 final  String? message;
 final  BridgeTurnFailureDto? turnFailure;
 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItem_TurnOutcomeCopyWith<BridgeTimelineItem_TurnOutcome> get copyWith => _$BridgeTimelineItem_TurnOutcomeCopyWithImpl<BridgeTimelineItem_TurnOutcome>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem_TurnOutcome&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.message, message) || other.message == message)&&(identical(other.turnFailure, turnFailure) || other.turnFailure == turnFailure)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,turnId,inputId,outcome,message,turnFailure,occurredAtMs);
}

@override
String toString() {
    return 'BridgeTimelineItem.turnOutcome(id: $id, seq: $seq, turnId: $turnId, inputId: $inputId, outcome: $outcome, message: $message, turnFailure: $turnFailure, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItem_TurnOutcomeCopyWith<$Res> implements $BridgeTimelineItemCopyWith<$Res> {
  factory $BridgeTimelineItem_TurnOutcomeCopyWith(BridgeTimelineItem_TurnOutcome value, $Res Function(BridgeTimelineItem_TurnOutcome) _then) = _$BridgeTimelineItem_TurnOutcomeCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String? turnId, String? inputId, String outcome, String? message, BridgeTurnFailureDto? turnFailure, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeTimelineItem_TurnOutcomeCopyWithImpl<$Res>
    implements $BridgeTimelineItem_TurnOutcomeCopyWith<$Res> {
  _$BridgeTimelineItem_TurnOutcomeCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem_TurnOutcome _self;
  final $Res Function(BridgeTimelineItem_TurnOutcome) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? turnId = freezed,Object? inputId = freezed,Object? outcome = null,Object? message = freezed,Object? turnFailure = freezed,Object? occurredAtMs = freezed,}) {
  return _then(BridgeTimelineItem_TurnOutcome(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String?,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,turnFailure: freezed == turnFailure ? _self.turnFailure : turnFailure // ignore: cast_nullable_to_non_nullable
as BridgeTurnFailureDto?,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeTimelineItem_StandaloneTool extends BridgeTimelineItem {
  const BridgeTimelineItem_StandaloneTool({required this.id, required this.seq, this.turnId, required this.callId, required this.toolName, this.presentationContract, required this.state, required this.summary, required this.payloadJson, required  List<BridgeBodyRef> bodies, this.occurredAtMs}): _bodies = bodies,super._();


@override final  String id;
 final  BigInt seq;
 final  String? turnId;
 final  String callId;
 final  String toolName;
 final  String? presentationContract;
 final  String state;
 final  String summary;
 final  String payloadJson;
 final  List<BridgeBodyRef> _bodies;
 List<BridgeBodyRef> get bodies {
  if (_bodies is EqualUnmodifiableListView) return _bodies;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bodies);
}

 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItem_StandaloneToolCopyWith<BridgeTimelineItem_StandaloneTool> get copyWith => _$BridgeTimelineItem_StandaloneToolCopyWithImpl<BridgeTimelineItem_StandaloneTool>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem_StandaloneTool&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.callId, callId) || other.callId == callId)&&(identical(other.toolName, toolName) || other.toolName == toolName)&&(identical(other.presentationContract, presentationContract) || other.presentationContract == presentationContract)&&(identical(other.state, state) || other.state == state)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.payloadJson, payloadJson) || other.payloadJson == payloadJson)&&const DeepCollectionEquality().equals(other.bodies, _bodies)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,turnId,callId,toolName,presentationContract,state,summary,payloadJson,const DeepCollectionEquality().hash(_bodies),occurredAtMs);
}

@override
String toString() {
    return 'BridgeTimelineItem.standaloneTool(id: $id, seq: $seq, turnId: $turnId, callId: $callId, toolName: $toolName, presentationContract: $presentationContract, state: $state, summary: $summary, payloadJson: $payloadJson, bodies: $bodies, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItem_StandaloneToolCopyWith<$Res> implements $BridgeTimelineItemCopyWith<$Res> {
  factory $BridgeTimelineItem_StandaloneToolCopyWith(BridgeTimelineItem_StandaloneTool value, $Res Function(BridgeTimelineItem_StandaloneTool) _then) = _$BridgeTimelineItem_StandaloneToolCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String? turnId, String callId, String toolName, String? presentationContract, String state, String summary, String payloadJson, List<BridgeBodyRef> bodies, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeTimelineItem_StandaloneToolCopyWithImpl<$Res>
    implements $BridgeTimelineItem_StandaloneToolCopyWith<$Res> {
  _$BridgeTimelineItem_StandaloneToolCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem_StandaloneTool _self;
  final $Res Function(BridgeTimelineItem_StandaloneTool) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? turnId = freezed,Object? callId = null,Object? toolName = null,Object? presentationContract = freezed,Object? state = null,Object? summary = null,Object? payloadJson = null,Object? bodies = null,Object? occurredAtMs = freezed,}) {
  return _then(BridgeTimelineItem_StandaloneTool(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String,toolName: null == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as String,presentationContract: freezed == presentationContract ? _self.presentationContract : presentationContract // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,payloadJson: null == payloadJson ? _self.payloadJson : payloadJson // ignore: cast_nullable_to_non_nullable
as String,bodies: null == bodies ? _self._bodies : bodies // ignore: cast_nullable_to_non_nullable
as List<BridgeBodyRef>,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeTimelineItem_Fallback extends BridgeTimelineItem {
  const BridgeTimelineItem_Fallback({required this.id, required this.seq, required this.eventId, required this.eventKind, required this.reason, this.rawPreview, this.occurredAtMs}): super._();


@override final  String id;
 final  BigInt seq;
 final  String eventId;
 final  String eventKind;
 final  String reason;
 final  String? rawPreview;
 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineItem_FallbackCopyWith<BridgeTimelineItem_Fallback> get copyWith => _$BridgeTimelineItem_FallbackCopyWithImpl<BridgeTimelineItem_Fallback>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineItem_Fallback&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.eventId, eventId) || other.eventId == eventId)&&(identical(other.eventKind, eventKind) || other.eventKind == eventKind)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.rawPreview, rawPreview) || other.rawPreview == rawPreview)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,eventId,eventKind,reason,rawPreview,occurredAtMs);
}

@override
String toString() {
    return 'BridgeTimelineItem.fallback(id: $id, seq: $seq, eventId: $eventId, eventKind: $eventKind, reason: $reason, rawPreview: $rawPreview, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineItem_FallbackCopyWith<$Res> implements $BridgeTimelineItemCopyWith<$Res> {
  factory $BridgeTimelineItem_FallbackCopyWith(BridgeTimelineItem_Fallback value, $Res Function(BridgeTimelineItem_Fallback) _then) = _$BridgeTimelineItem_FallbackCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String eventId, String eventKind, String reason, String? rawPreview, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeTimelineItem_FallbackCopyWithImpl<$Res>
    implements $BridgeTimelineItem_FallbackCopyWith<$Res> {
  _$BridgeTimelineItem_FallbackCopyWithImpl(this._self, this._then);

  final BridgeTimelineItem_Fallback _self;
  final $Res Function(BridgeTimelineItem_Fallback) _then;

/// Create a copy of BridgeTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? eventId = null,Object? eventKind = null,Object? reason = null,Object? rawPreview = freezed,Object? occurredAtMs = freezed,}) {
  return _then(BridgeTimelineItem_Fallback(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,eventId: null == eventId ? _self.eventId : eventId // ignore: cast_nullable_to_non_nullable
as String,eventKind: null == eventKind ? _self.eventKind : eventKind // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,rawPreview: freezed == rawPreview ? _self.rawPreview : rawPreview // ignore: cast_nullable_to_non_nullable
as String?,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelinePatch {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelinePatch);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelinePatch()';
}


}

/// @nodoc
class $BridgeTimelinePatchCopyWith<$Res>  {
$BridgeTimelinePatchCopyWith(BridgeTimelinePatch _, $Res Function(BridgeTimelinePatch) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelinePatch].
extension BridgeTimelinePatchPatterns on BridgeTimelinePatch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelinePatch_Reset value)?  reset,TResult Function( BridgeTimelinePatch_PrependOlder value)?  prependOlder,TResult Function( BridgeTimelinePatch_Append value)?  append,TResult Function( BridgeTimelinePatch_Update value)?  update,TResult Function( BridgeTimelinePatch_Remove value)?  remove,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelinePatch_Reset() when reset != null:
return reset(_that);case BridgeTimelinePatch_PrependOlder() when prependOlder != null:
return prependOlder(_that);case BridgeTimelinePatch_Append() when append != null:
return append(_that);case BridgeTimelinePatch_Update() when update != null:
return update(_that);case BridgeTimelinePatch_Remove() when remove != null:
return remove(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelinePatch_Reset value)  reset,required TResult Function( BridgeTimelinePatch_PrependOlder value)  prependOlder,required TResult Function( BridgeTimelinePatch_Append value)  append,required TResult Function( BridgeTimelinePatch_Update value)  update,required TResult Function( BridgeTimelinePatch_Remove value)  remove,}){
final _that = this;
switch (_that) {
case BridgeTimelinePatch_Reset():
return reset(_that);case BridgeTimelinePatch_PrependOlder():
return prependOlder(_that);case BridgeTimelinePatch_Append():
return append(_that);case BridgeTimelinePatch_Update():
return update(_that);case BridgeTimelinePatch_Remove():
return remove(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelinePatch_Reset value)?  reset,TResult? Function( BridgeTimelinePatch_PrependOlder value)?  prependOlder,TResult? Function( BridgeTimelinePatch_Append value)?  append,TResult? Function( BridgeTimelinePatch_Update value)?  update,TResult? Function( BridgeTimelinePatch_Remove value)?  remove,}){
final _that = this;
switch (_that) {
case BridgeTimelinePatch_Reset() when reset != null:
return reset(_that);case BridgeTimelinePatch_PrependOlder() when prependOlder != null:
return prependOlder(_that);case BridgeTimelinePatch_Append() when append != null:
return append(_that);case BridgeTimelinePatch_Update() when update != null:
return update(_that);case BridgeTimelinePatch_Remove() when remove != null:
return remove(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<BridgeTimelineItem> items,  bool hasMoreOlder,  String? olderCursor,  BigInt revision)?  reset,TResult Function( List<BridgeTimelineItem> items,  bool hasMoreOlder,  String? olderCursor)?  prependOlder,TResult Function( List<BridgeTimelineItem> items)?  append,TResult Function( BridgeTimelineItem item)?  update,TResult Function( String itemId)?  remove,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelinePatch_Reset() when reset != null:
return reset(_that.items,_that.hasMoreOlder,_that.olderCursor,_that.revision);case BridgeTimelinePatch_PrependOlder() when prependOlder != null:
return prependOlder(_that.items,_that.hasMoreOlder,_that.olderCursor);case BridgeTimelinePatch_Append() when append != null:
return append(_that.items);case BridgeTimelinePatch_Update() when update != null:
return update(_that.item);case BridgeTimelinePatch_Remove() when remove != null:
return remove(_that.itemId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<BridgeTimelineItem> items,  bool hasMoreOlder,  String? olderCursor,  BigInt revision)  reset,required TResult Function( List<BridgeTimelineItem> items,  bool hasMoreOlder,  String? olderCursor)  prependOlder,required TResult Function( List<BridgeTimelineItem> items)  append,required TResult Function( BridgeTimelineItem item)  update,required TResult Function( String itemId)  remove,}) {final _that = this;
switch (_that) {
case BridgeTimelinePatch_Reset():
return reset(_that.items,_that.hasMoreOlder,_that.olderCursor,_that.revision);case BridgeTimelinePatch_PrependOlder():
return prependOlder(_that.items,_that.hasMoreOlder,_that.olderCursor);case BridgeTimelinePatch_Append():
return append(_that.items);case BridgeTimelinePatch_Update():
return update(_that.item);case BridgeTimelinePatch_Remove():
return remove(_that.itemId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<BridgeTimelineItem> items,  bool hasMoreOlder,  String? olderCursor,  BigInt revision)?  reset,TResult? Function( List<BridgeTimelineItem> items,  bool hasMoreOlder,  String? olderCursor)?  prependOlder,TResult? Function( List<BridgeTimelineItem> items)?  append,TResult? Function( BridgeTimelineItem item)?  update,TResult? Function( String itemId)?  remove,}) {final _that = this;
switch (_that) {
case BridgeTimelinePatch_Reset() when reset != null:
return reset(_that.items,_that.hasMoreOlder,_that.olderCursor,_that.revision);case BridgeTimelinePatch_PrependOlder() when prependOlder != null:
return prependOlder(_that.items,_that.hasMoreOlder,_that.olderCursor);case BridgeTimelinePatch_Append() when append != null:
return append(_that.items);case BridgeTimelinePatch_Update() when update != null:
return update(_that.item);case BridgeTimelinePatch_Remove() when remove != null:
return remove(_that.itemId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelinePatch_Reset extends BridgeTimelinePatch {
  const BridgeTimelinePatch_Reset({required  List<BridgeTimelineItem> items, required this.hasMoreOlder, this.olderCursor, required this.revision}): _items = items,super._();


 final  List<BridgeTimelineItem> _items;
 List<BridgeTimelineItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

 final  bool hasMoreOlder;
 final  String? olderCursor;
 final  BigInt revision;

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelinePatch_ResetCopyWith<BridgeTimelinePatch_Reset> get copyWith => _$BridgeTimelinePatch_ResetCopyWithImpl<BridgeTimelinePatch_Reset>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelinePatch_Reset&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.hasMoreOlder, hasMoreOlder) || other.hasMoreOlder == hasMoreOlder)&&(identical(other.olderCursor, olderCursor) || other.olderCursor == olderCursor)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),hasMoreOlder,olderCursor,revision);
}

@override
String toString() {
    return 'BridgeTimelinePatch.reset(items: $items, hasMoreOlder: $hasMoreOlder, olderCursor: $olderCursor, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelinePatch_ResetCopyWith<$Res> implements $BridgeTimelinePatchCopyWith<$Res> {
  factory $BridgeTimelinePatch_ResetCopyWith(BridgeTimelinePatch_Reset value, $Res Function(BridgeTimelinePatch_Reset) _then) = _$BridgeTimelinePatch_ResetCopyWithImpl;
@useResult
$Res call({
 List<BridgeTimelineItem> items, bool hasMoreOlder, String? olderCursor, BigInt revision
});




}
/// @nodoc
class _$BridgeTimelinePatch_ResetCopyWithImpl<$Res>
    implements $BridgeTimelinePatch_ResetCopyWith<$Res> {
  _$BridgeTimelinePatch_ResetCopyWithImpl(this._self, this._then);

  final BridgeTimelinePatch_Reset _self;
  final $Res Function(BridgeTimelinePatch_Reset) _then;

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? items = null,Object? hasMoreOlder = null,Object? olderCursor = freezed,Object? revision = null,}) {
  return _then(BridgeTimelinePatch_Reset(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<BridgeTimelineItem>,hasMoreOlder: null == hasMoreOlder ? _self.hasMoreOlder : hasMoreOlder // ignore: cast_nullable_to_non_nullable
as bool,olderCursor: freezed == olderCursor ? _self.olderCursor : olderCursor // ignore: cast_nullable_to_non_nullable
as String?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeTimelinePatch_PrependOlder extends BridgeTimelinePatch {
  const BridgeTimelinePatch_PrependOlder({required  List<BridgeTimelineItem> items, required this.hasMoreOlder, this.olderCursor}): _items = items,super._();


 final  List<BridgeTimelineItem> _items;
 List<BridgeTimelineItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

 final  bool hasMoreOlder;
 final  String? olderCursor;

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelinePatch_PrependOlderCopyWith<BridgeTimelinePatch_PrependOlder> get copyWith => _$BridgeTimelinePatch_PrependOlderCopyWithImpl<BridgeTimelinePatch_PrependOlder>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelinePatch_PrependOlder&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.hasMoreOlder, hasMoreOlder) || other.hasMoreOlder == hasMoreOlder)&&(identical(other.olderCursor, olderCursor) || other.olderCursor == olderCursor));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),hasMoreOlder,olderCursor);
}

@override
String toString() {
    return 'BridgeTimelinePatch.prependOlder(items: $items, hasMoreOlder: $hasMoreOlder, olderCursor: $olderCursor)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelinePatch_PrependOlderCopyWith<$Res> implements $BridgeTimelinePatchCopyWith<$Res> {
  factory $BridgeTimelinePatch_PrependOlderCopyWith(BridgeTimelinePatch_PrependOlder value, $Res Function(BridgeTimelinePatch_PrependOlder) _then) = _$BridgeTimelinePatch_PrependOlderCopyWithImpl;
@useResult
$Res call({
 List<BridgeTimelineItem> items, bool hasMoreOlder, String? olderCursor
});




}
/// @nodoc
class _$BridgeTimelinePatch_PrependOlderCopyWithImpl<$Res>
    implements $BridgeTimelinePatch_PrependOlderCopyWith<$Res> {
  _$BridgeTimelinePatch_PrependOlderCopyWithImpl(this._self, this._then);

  final BridgeTimelinePatch_PrependOlder _self;
  final $Res Function(BridgeTimelinePatch_PrependOlder) _then;

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? items = null,Object? hasMoreOlder = null,Object? olderCursor = freezed,}) {
  return _then(BridgeTimelinePatch_PrependOlder(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<BridgeTimelineItem>,hasMoreOlder: null == hasMoreOlder ? _self.hasMoreOlder : hasMoreOlder // ignore: cast_nullable_to_non_nullable
as bool,olderCursor: freezed == olderCursor ? _self.olderCursor : olderCursor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BridgeTimelinePatch_Append extends BridgeTimelinePatch {
  const BridgeTimelinePatch_Append({required  List<BridgeTimelineItem> items}): _items = items,super._();


 final  List<BridgeTimelineItem> _items;
 List<BridgeTimelineItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}


/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelinePatch_AppendCopyWith<BridgeTimelinePatch_Append> get copyWith => _$BridgeTimelinePatch_AppendCopyWithImpl<BridgeTimelinePatch_Append>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelinePatch_Append&&const DeepCollectionEquality().equals(other.items, _items));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_items));
}

@override
String toString() {
    return 'BridgeTimelinePatch.append(items: $items)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelinePatch_AppendCopyWith<$Res> implements $BridgeTimelinePatchCopyWith<$Res> {
  factory $BridgeTimelinePatch_AppendCopyWith(BridgeTimelinePatch_Append value, $Res Function(BridgeTimelinePatch_Append) _then) = _$BridgeTimelinePatch_AppendCopyWithImpl;
@useResult
$Res call({
 List<BridgeTimelineItem> items
});




}
/// @nodoc
class _$BridgeTimelinePatch_AppendCopyWithImpl<$Res>
    implements $BridgeTimelinePatch_AppendCopyWith<$Res> {
  _$BridgeTimelinePatch_AppendCopyWithImpl(this._self, this._then);

  final BridgeTimelinePatch_Append _self;
  final $Res Function(BridgeTimelinePatch_Append) _then;

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? items = null,}) {
  return _then(BridgeTimelinePatch_Append(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<BridgeTimelineItem>,
  ));
}


}

/// @nodoc


class BridgeTimelinePatch_Update extends BridgeTimelinePatch {
  const BridgeTimelinePatch_Update({required this.item}): super._();


 final  BridgeTimelineItem item;

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelinePatch_UpdateCopyWith<BridgeTimelinePatch_Update> get copyWith => _$BridgeTimelinePatch_UpdateCopyWithImpl<BridgeTimelinePatch_Update>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelinePatch_Update&&(identical(other.item, item) || other.item == item));
}


@override
int get hashCode {
    return Object.hash(runtimeType,item);
}

@override
String toString() {
    return 'BridgeTimelinePatch.update(item: $item)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelinePatch_UpdateCopyWith<$Res> implements $BridgeTimelinePatchCopyWith<$Res> {
  factory $BridgeTimelinePatch_UpdateCopyWith(BridgeTimelinePatch_Update value, $Res Function(BridgeTimelinePatch_Update) _then) = _$BridgeTimelinePatch_UpdateCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineItem item
});


$BridgeTimelineItemCopyWith<$Res> get item;

}
/// @nodoc
class _$BridgeTimelinePatch_UpdateCopyWithImpl<$Res>
    implements $BridgeTimelinePatch_UpdateCopyWith<$Res> {
  _$BridgeTimelinePatch_UpdateCopyWithImpl(this._self, this._then);

  final BridgeTimelinePatch_Update _self;
  final $Res Function(BridgeTimelinePatch_Update) _then;

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? item = null,}) {
  return _then(BridgeTimelinePatch_Update(
item: null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as BridgeTimelineItem,
  ));
}

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeTimelineItemCopyWith<$Res> get item {

  return $BridgeTimelineItemCopyWith<$Res>(_self.item, (value) {
    return _then(_self.copyWith(item: value));
  });
}
}

/// @nodoc


class BridgeTimelinePatch_Remove extends BridgeTimelinePatch {
  const BridgeTimelinePatch_Remove({required this.itemId}): super._();


 final  String itemId;

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelinePatch_RemoveCopyWith<BridgeTimelinePatch_Remove> get copyWith => _$BridgeTimelinePatch_RemoveCopyWithImpl<BridgeTimelinePatch_Remove>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelinePatch_Remove&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId);
}

@override
String toString() {
    return 'BridgeTimelinePatch.remove(itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelinePatch_RemoveCopyWith<$Res> implements $BridgeTimelinePatchCopyWith<$Res> {
  factory $BridgeTimelinePatch_RemoveCopyWith(BridgeTimelinePatch_Remove value, $Res Function(BridgeTimelinePatch_Remove) _then) = _$BridgeTimelinePatch_RemoveCopyWithImpl;
@useResult
$Res call({
 String itemId
});




}
/// @nodoc
class _$BridgeTimelinePatch_RemoveCopyWithImpl<$Res>
    implements $BridgeTimelinePatch_RemoveCopyWith<$Res> {
  _$BridgeTimelinePatch_RemoveCopyWithImpl(this._self, this._then);

  final BridgeTimelinePatch_Remove _self;
  final $Res Function(BridgeTimelinePatch_Remove) _then;

/// Create a copy of BridgeTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,}) {
  return _then(BridgeTimelinePatch_Remove(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeWorkGroupMember {

 String get id; BigInt get seq;
/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWorkGroupMemberCopyWith<BridgeWorkGroupMember> get copyWith => _$BridgeWorkGroupMemberCopyWithImpl<BridgeWorkGroupMember>(this as BridgeWorkGroupMember, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeWorkGroupMember;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkGroupMember&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.seq, _this.seq) || other.seq == _this.seq));
}


@override
int get hashCode {
  final _this = this as BridgeWorkGroupMember;
  return Object.hash(runtimeType,_this.id,_this.seq);
}

@override
String toString() {
  final _this = this as BridgeWorkGroupMember;
  return 'BridgeWorkGroupMember(id: ${_this.id}, seq: ${_this.seq})';
}


}

/// @nodoc
abstract mixin class $BridgeWorkGroupMemberCopyWith<$Res>  {
  factory $BridgeWorkGroupMemberCopyWith(BridgeWorkGroupMember value, $Res Function(BridgeWorkGroupMember) _then) = _$BridgeWorkGroupMemberCopyWithImpl;
@useResult
$Res call({
 String id, BigInt seq
});




}
/// @nodoc
class _$BridgeWorkGroupMemberCopyWithImpl<$Res>
    implements $BridgeWorkGroupMemberCopyWith<$Res> {
  _$BridgeWorkGroupMemberCopyWithImpl(this._self, this._then);

  final BridgeWorkGroupMember _self;
  final $Res Function(BridgeWorkGroupMember) _then;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? seq = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeWorkGroupMember].
extension BridgeWorkGroupMemberPatterns on BridgeWorkGroupMember {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeWorkGroupMember_Reasoning value)?  reasoning,TResult Function( BridgeWorkGroupMember_ToolCall value)?  toolCall,TResult Function( BridgeWorkGroupMember_Agent value)?  agent,TResult Function( BridgeWorkGroupMember_FileChange value)?  fileChange,TResult Function( BridgeWorkGroupMember_Skill value)?  skill,TResult Function( BridgeWorkGroupMember_Fallback value)?  fallback,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeWorkGroupMember_Reasoning() when reasoning != null:
return reasoning(_that);case BridgeWorkGroupMember_ToolCall() when toolCall != null:
return toolCall(_that);case BridgeWorkGroupMember_Agent() when agent != null:
return agent(_that);case BridgeWorkGroupMember_FileChange() when fileChange != null:
return fileChange(_that);case BridgeWorkGroupMember_Skill() when skill != null:
return skill(_that);case BridgeWorkGroupMember_Fallback() when fallback != null:
return fallback(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeWorkGroupMember_Reasoning value)  reasoning,required TResult Function( BridgeWorkGroupMember_ToolCall value)  toolCall,required TResult Function( BridgeWorkGroupMember_Agent value)  agent,required TResult Function( BridgeWorkGroupMember_FileChange value)  fileChange,required TResult Function( BridgeWorkGroupMember_Skill value)  skill,required TResult Function( BridgeWorkGroupMember_Fallback value)  fallback,}){
final _that = this;
switch (_that) {
case BridgeWorkGroupMember_Reasoning():
return reasoning(_that);case BridgeWorkGroupMember_ToolCall():
return toolCall(_that);case BridgeWorkGroupMember_Agent():
return agent(_that);case BridgeWorkGroupMember_FileChange():
return fileChange(_that);case BridgeWorkGroupMember_Skill():
return skill(_that);case BridgeWorkGroupMember_Fallback():
return fallback(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeWorkGroupMember_Reasoning value)?  reasoning,TResult? Function( BridgeWorkGroupMember_ToolCall value)?  toolCall,TResult? Function( BridgeWorkGroupMember_Agent value)?  agent,TResult? Function( BridgeWorkGroupMember_FileChange value)?  fileChange,TResult? Function( BridgeWorkGroupMember_Skill value)?  skill,TResult? Function( BridgeWorkGroupMember_Fallback value)?  fallback,}){
final _that = this;
switch (_that) {
case BridgeWorkGroupMember_Reasoning() when reasoning != null:
return reasoning(_that);case BridgeWorkGroupMember_ToolCall() when toolCall != null:
return toolCall(_that);case BridgeWorkGroupMember_Agent() when agent != null:
return agent(_that);case BridgeWorkGroupMember_FileChange() when fileChange != null:
return fileChange(_that);case BridgeWorkGroupMember_Skill() when skill != null:
return skill(_that);case BridgeWorkGroupMember_Fallback() when fallback != null:
return fallback(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  BigInt seq,  String text,  String summary,  BridgeBodyRef? bodyRef,  String outcome,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)?  reasoning,TResult Function( String id,  BigInt seq,  String callId,  String? turnId,  String toolName,  String? presentationContract,  String status,  String summary,  String? arguments,  String? resultPreview,  String payloadJson,  List<BridgeBodyRef> bodies,  String? waitJson,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)?  toolCall,TResult Function( String id,  BigInt seq,  String agentId,  String name,  String status,  String summary,  String payloadJson,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)?  agent,TResult Function( String id,  BigInt seq,  String summary,  String payloadJson,  List<BridgeBodyRef> bodies,  PlatformInt64? occurredAtMs)?  fileChange,TResult Function( String id,  BigInt seq,  String name,  String summary,  String payloadJson,  PlatformInt64? occurredAtMs)?  skill,TResult Function( String id,  BigInt seq,  String eventId,  String eventKind,  String reason,  PlatformInt64? occurredAtMs)?  fallback,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeWorkGroupMember_Reasoning() when reasoning != null:
return reasoning(_that.id,_that.seq,_that.text,_that.summary,_that.bodyRef,_that.outcome,_that.startedAtMs,_that.finishedAtMs);case BridgeWorkGroupMember_ToolCall() when toolCall != null:
return toolCall(_that.id,_that.seq,_that.callId,_that.turnId,_that.toolName,_that.presentationContract,_that.status,_that.summary,_that.arguments,_that.resultPreview,_that.payloadJson,_that.bodies,_that.waitJson,_that.startedAtMs,_that.finishedAtMs);case BridgeWorkGroupMember_Agent() when agent != null:
return agent(_that.id,_that.seq,_that.agentId,_that.name,_that.status,_that.summary,_that.payloadJson,_that.startedAtMs,_that.finishedAtMs);case BridgeWorkGroupMember_FileChange() when fileChange != null:
return fileChange(_that.id,_that.seq,_that.summary,_that.payloadJson,_that.bodies,_that.occurredAtMs);case BridgeWorkGroupMember_Skill() when skill != null:
return skill(_that.id,_that.seq,_that.name,_that.summary,_that.payloadJson,_that.occurredAtMs);case BridgeWorkGroupMember_Fallback() when fallback != null:
return fallback(_that.id,_that.seq,_that.eventId,_that.eventKind,_that.reason,_that.occurredAtMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  BigInt seq,  String text,  String summary,  BridgeBodyRef? bodyRef,  String outcome,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)  reasoning,required TResult Function( String id,  BigInt seq,  String callId,  String? turnId,  String toolName,  String? presentationContract,  String status,  String summary,  String? arguments,  String? resultPreview,  String payloadJson,  List<BridgeBodyRef> bodies,  String? waitJson,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)  toolCall,required TResult Function( String id,  BigInt seq,  String agentId,  String name,  String status,  String summary,  String payloadJson,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)  agent,required TResult Function( String id,  BigInt seq,  String summary,  String payloadJson,  List<BridgeBodyRef> bodies,  PlatformInt64? occurredAtMs)  fileChange,required TResult Function( String id,  BigInt seq,  String name,  String summary,  String payloadJson,  PlatformInt64? occurredAtMs)  skill,required TResult Function( String id,  BigInt seq,  String eventId,  String eventKind,  String reason,  PlatformInt64? occurredAtMs)  fallback,}) {final _that = this;
switch (_that) {
case BridgeWorkGroupMember_Reasoning():
return reasoning(_that.id,_that.seq,_that.text,_that.summary,_that.bodyRef,_that.outcome,_that.startedAtMs,_that.finishedAtMs);case BridgeWorkGroupMember_ToolCall():
return toolCall(_that.id,_that.seq,_that.callId,_that.turnId,_that.toolName,_that.presentationContract,_that.status,_that.summary,_that.arguments,_that.resultPreview,_that.payloadJson,_that.bodies,_that.waitJson,_that.startedAtMs,_that.finishedAtMs);case BridgeWorkGroupMember_Agent():
return agent(_that.id,_that.seq,_that.agentId,_that.name,_that.status,_that.summary,_that.payloadJson,_that.startedAtMs,_that.finishedAtMs);case BridgeWorkGroupMember_FileChange():
return fileChange(_that.id,_that.seq,_that.summary,_that.payloadJson,_that.bodies,_that.occurredAtMs);case BridgeWorkGroupMember_Skill():
return skill(_that.id,_that.seq,_that.name,_that.summary,_that.payloadJson,_that.occurredAtMs);case BridgeWorkGroupMember_Fallback():
return fallback(_that.id,_that.seq,_that.eventId,_that.eventKind,_that.reason,_that.occurredAtMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  BigInt seq,  String text,  String summary,  BridgeBodyRef? bodyRef,  String outcome,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)?  reasoning,TResult? Function( String id,  BigInt seq,  String callId,  String? turnId,  String toolName,  String? presentationContract,  String status,  String summary,  String? arguments,  String? resultPreview,  String payloadJson,  List<BridgeBodyRef> bodies,  String? waitJson,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)?  toolCall,TResult? Function( String id,  BigInt seq,  String agentId,  String name,  String status,  String summary,  String payloadJson,  PlatformInt64? startedAtMs,  PlatformInt64? finishedAtMs)?  agent,TResult? Function( String id,  BigInt seq,  String summary,  String payloadJson,  List<BridgeBodyRef> bodies,  PlatformInt64? occurredAtMs)?  fileChange,TResult? Function( String id,  BigInt seq,  String name,  String summary,  String payloadJson,  PlatformInt64? occurredAtMs)?  skill,TResult? Function( String id,  BigInt seq,  String eventId,  String eventKind,  String reason,  PlatformInt64? occurredAtMs)?  fallback,}) {final _that = this;
switch (_that) {
case BridgeWorkGroupMember_Reasoning() when reasoning != null:
return reasoning(_that.id,_that.seq,_that.text,_that.summary,_that.bodyRef,_that.outcome,_that.startedAtMs,_that.finishedAtMs);case BridgeWorkGroupMember_ToolCall() when toolCall != null:
return toolCall(_that.id,_that.seq,_that.callId,_that.turnId,_that.toolName,_that.presentationContract,_that.status,_that.summary,_that.arguments,_that.resultPreview,_that.payloadJson,_that.bodies,_that.waitJson,_that.startedAtMs,_that.finishedAtMs);case BridgeWorkGroupMember_Agent() when agent != null:
return agent(_that.id,_that.seq,_that.agentId,_that.name,_that.status,_that.summary,_that.payloadJson,_that.startedAtMs,_that.finishedAtMs);case BridgeWorkGroupMember_FileChange() when fileChange != null:
return fileChange(_that.id,_that.seq,_that.summary,_that.payloadJson,_that.bodies,_that.occurredAtMs);case BridgeWorkGroupMember_Skill() when skill != null:
return skill(_that.id,_that.seq,_that.name,_that.summary,_that.payloadJson,_that.occurredAtMs);case BridgeWorkGroupMember_Fallback() when fallback != null:
return fallback(_that.id,_that.seq,_that.eventId,_that.eventKind,_that.reason,_that.occurredAtMs);case _:
  return null;

}
}

}

/// @nodoc


class BridgeWorkGroupMember_Reasoning extends BridgeWorkGroupMember {
  const BridgeWorkGroupMember_Reasoning({required this.id, required this.seq, required this.text, required this.summary, this.bodyRef, required this.outcome, this.startedAtMs, this.finishedAtMs}): super._();


@override final  String id;
@override final  BigInt seq;
 final  String text;
 final  String summary;
 final  BridgeBodyRef? bodyRef;
 final  String outcome;
 final  PlatformInt64? startedAtMs;
 final  PlatformInt64? finishedAtMs;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWorkGroupMember_ReasoningCopyWith<BridgeWorkGroupMember_Reasoning> get copyWith => _$BridgeWorkGroupMember_ReasoningCopyWithImpl<BridgeWorkGroupMember_Reasoning>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkGroupMember_Reasoning&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.text, text) || other.text == text)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.bodyRef, bodyRef) || other.bodyRef == bodyRef)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.finishedAtMs, finishedAtMs) || other.finishedAtMs == finishedAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,text,summary,bodyRef,outcome,startedAtMs,finishedAtMs);
}

@override
String toString() {
    return 'BridgeWorkGroupMember.reasoning(id: $id, seq: $seq, text: $text, summary: $summary, bodyRef: $bodyRef, outcome: $outcome, startedAtMs: $startedAtMs, finishedAtMs: $finishedAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeWorkGroupMember_ReasoningCopyWith<$Res> implements $BridgeWorkGroupMemberCopyWith<$Res> {
  factory $BridgeWorkGroupMember_ReasoningCopyWith(BridgeWorkGroupMember_Reasoning value, $Res Function(BridgeWorkGroupMember_Reasoning) _then) = _$BridgeWorkGroupMember_ReasoningCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String text, String summary, BridgeBodyRef? bodyRef, String outcome, PlatformInt64? startedAtMs, PlatformInt64? finishedAtMs
});




}
/// @nodoc
class _$BridgeWorkGroupMember_ReasoningCopyWithImpl<$Res>
    implements $BridgeWorkGroupMember_ReasoningCopyWith<$Res> {
  _$BridgeWorkGroupMember_ReasoningCopyWithImpl(this._self, this._then);

  final BridgeWorkGroupMember_Reasoning _self;
  final $Res Function(BridgeWorkGroupMember_Reasoning) _then;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? text = null,Object? summary = null,Object? bodyRef = freezed,Object? outcome = null,Object? startedAtMs = freezed,Object? finishedAtMs = freezed,}) {
  return _then(BridgeWorkGroupMember_Reasoning(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,bodyRef: freezed == bodyRef ? _self.bodyRef : bodyRef // ignore: cast_nullable_to_non_nullable
as BridgeBodyRef?,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,finishedAtMs: freezed == finishedAtMs ? _self.finishedAtMs : finishedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeWorkGroupMember_ToolCall extends BridgeWorkGroupMember {
  const BridgeWorkGroupMember_ToolCall({required this.id, required this.seq, required this.callId, this.turnId, required this.toolName, this.presentationContract, required this.status, required this.summary, this.arguments, this.resultPreview, required this.payloadJson, required  List<BridgeBodyRef> bodies, this.waitJson, this.startedAtMs, this.finishedAtMs}): _bodies = bodies,super._();


@override final  String id;
@override final  BigInt seq;
 final  String callId;
 final  String? turnId;
 final  String toolName;
 final  String? presentationContract;
 final  String status;
 final  String summary;
 final  String? arguments;
 final  String? resultPreview;
 final  String payloadJson;
 final  List<BridgeBodyRef> _bodies;
 List<BridgeBodyRef> get bodies {
  if (_bodies is EqualUnmodifiableListView) return _bodies;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bodies);
}

 final  String? waitJson;
 final  PlatformInt64? startedAtMs;
 final  PlatformInt64? finishedAtMs;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWorkGroupMember_ToolCallCopyWith<BridgeWorkGroupMember_ToolCall> get copyWith => _$BridgeWorkGroupMember_ToolCallCopyWithImpl<BridgeWorkGroupMember_ToolCall>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkGroupMember_ToolCall&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.callId, callId) || other.callId == callId)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.toolName, toolName) || other.toolName == toolName)&&(identical(other.presentationContract, presentationContract) || other.presentationContract == presentationContract)&&(identical(other.status, status) || other.status == status)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.arguments, arguments) || other.arguments == arguments)&&(identical(other.resultPreview, resultPreview) || other.resultPreview == resultPreview)&&(identical(other.payloadJson, payloadJson) || other.payloadJson == payloadJson)&&const DeepCollectionEquality().equals(other.bodies, _bodies)&&(identical(other.waitJson, waitJson) || other.waitJson == waitJson)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.finishedAtMs, finishedAtMs) || other.finishedAtMs == finishedAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,callId,turnId,toolName,presentationContract,status,summary,arguments,resultPreview,payloadJson,const DeepCollectionEquality().hash(_bodies),waitJson,startedAtMs,finishedAtMs);
}

@override
String toString() {
    return 'BridgeWorkGroupMember.toolCall(id: $id, seq: $seq, callId: $callId, turnId: $turnId, toolName: $toolName, presentationContract: $presentationContract, status: $status, summary: $summary, arguments: $arguments, resultPreview: $resultPreview, payloadJson: $payloadJson, bodies: $bodies, waitJson: $waitJson, startedAtMs: $startedAtMs, finishedAtMs: $finishedAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeWorkGroupMember_ToolCallCopyWith<$Res> implements $BridgeWorkGroupMemberCopyWith<$Res> {
  factory $BridgeWorkGroupMember_ToolCallCopyWith(BridgeWorkGroupMember_ToolCall value, $Res Function(BridgeWorkGroupMember_ToolCall) _then) = _$BridgeWorkGroupMember_ToolCallCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String callId, String? turnId, String toolName, String? presentationContract, String status, String summary, String? arguments, String? resultPreview, String payloadJson, List<BridgeBodyRef> bodies, String? waitJson, PlatformInt64? startedAtMs, PlatformInt64? finishedAtMs
});




}
/// @nodoc
class _$BridgeWorkGroupMember_ToolCallCopyWithImpl<$Res>
    implements $BridgeWorkGroupMember_ToolCallCopyWith<$Res> {
  _$BridgeWorkGroupMember_ToolCallCopyWithImpl(this._self, this._then);

  final BridgeWorkGroupMember_ToolCall _self;
  final $Res Function(BridgeWorkGroupMember_ToolCall) _then;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? callId = null,Object? turnId = freezed,Object? toolName = null,Object? presentationContract = freezed,Object? status = null,Object? summary = null,Object? arguments = freezed,Object? resultPreview = freezed,Object? payloadJson = null,Object? bodies = null,Object? waitJson = freezed,Object? startedAtMs = freezed,Object? finishedAtMs = freezed,}) {
  return _then(BridgeWorkGroupMember_ToolCall(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,toolName: null == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as String,presentationContract: freezed == presentationContract ? _self.presentationContract : presentationContract // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,arguments: freezed == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as String?,resultPreview: freezed == resultPreview ? _self.resultPreview : resultPreview // ignore: cast_nullable_to_non_nullable
as String?,payloadJson: null == payloadJson ? _self.payloadJson : payloadJson // ignore: cast_nullable_to_non_nullable
as String,bodies: null == bodies ? _self._bodies : bodies // ignore: cast_nullable_to_non_nullable
as List<BridgeBodyRef>,waitJson: freezed == waitJson ? _self.waitJson : waitJson // ignore: cast_nullable_to_non_nullable
as String?,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,finishedAtMs: freezed == finishedAtMs ? _self.finishedAtMs : finishedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeWorkGroupMember_Agent extends BridgeWorkGroupMember {
  const BridgeWorkGroupMember_Agent({required this.id, required this.seq, required this.agentId, required this.name, required this.status, required this.summary, required this.payloadJson, this.startedAtMs, this.finishedAtMs}): super._();


@override final  String id;
@override final  BigInt seq;
 final  String agentId;
 final  String name;
 final  String status;
 final  String summary;
 final  String payloadJson;
 final  PlatformInt64? startedAtMs;
 final  PlatformInt64? finishedAtMs;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWorkGroupMember_AgentCopyWith<BridgeWorkGroupMember_Agent> get copyWith => _$BridgeWorkGroupMember_AgentCopyWithImpl<BridgeWorkGroupMember_Agent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkGroupMember_Agent&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.agentId, agentId) || other.agentId == agentId)&&(identical(other.name, name) || other.name == name)&&(identical(other.status, status) || other.status == status)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.payloadJson, payloadJson) || other.payloadJson == payloadJson)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.finishedAtMs, finishedAtMs) || other.finishedAtMs == finishedAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,agentId,name,status,summary,payloadJson,startedAtMs,finishedAtMs);
}

@override
String toString() {
    return 'BridgeWorkGroupMember.agent(id: $id, seq: $seq, agentId: $agentId, name: $name, status: $status, summary: $summary, payloadJson: $payloadJson, startedAtMs: $startedAtMs, finishedAtMs: $finishedAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeWorkGroupMember_AgentCopyWith<$Res> implements $BridgeWorkGroupMemberCopyWith<$Res> {
  factory $BridgeWorkGroupMember_AgentCopyWith(BridgeWorkGroupMember_Agent value, $Res Function(BridgeWorkGroupMember_Agent) _then) = _$BridgeWorkGroupMember_AgentCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String agentId, String name, String status, String summary, String payloadJson, PlatformInt64? startedAtMs, PlatformInt64? finishedAtMs
});




}
/// @nodoc
class _$BridgeWorkGroupMember_AgentCopyWithImpl<$Res>
    implements $BridgeWorkGroupMember_AgentCopyWith<$Res> {
  _$BridgeWorkGroupMember_AgentCopyWithImpl(this._self, this._then);

  final BridgeWorkGroupMember_Agent _self;
  final $Res Function(BridgeWorkGroupMember_Agent) _then;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? agentId = null,Object? name = null,Object? status = null,Object? summary = null,Object? payloadJson = null,Object? startedAtMs = freezed,Object? finishedAtMs = freezed,}) {
  return _then(BridgeWorkGroupMember_Agent(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,agentId: null == agentId ? _self.agentId : agentId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,payloadJson: null == payloadJson ? _self.payloadJson : payloadJson // ignore: cast_nullable_to_non_nullable
as String,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,finishedAtMs: freezed == finishedAtMs ? _self.finishedAtMs : finishedAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeWorkGroupMember_FileChange extends BridgeWorkGroupMember {
  const BridgeWorkGroupMember_FileChange({required this.id, required this.seq, required this.summary, required this.payloadJson, required  List<BridgeBodyRef> bodies, this.occurredAtMs}): _bodies = bodies,super._();


@override final  String id;
@override final  BigInt seq;
 final  String summary;
 final  String payloadJson;
 final  List<BridgeBodyRef> _bodies;
 List<BridgeBodyRef> get bodies {
  if (_bodies is EqualUnmodifiableListView) return _bodies;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bodies);
}

 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWorkGroupMember_FileChangeCopyWith<BridgeWorkGroupMember_FileChange> get copyWith => _$BridgeWorkGroupMember_FileChangeCopyWithImpl<BridgeWorkGroupMember_FileChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkGroupMember_FileChange&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.payloadJson, payloadJson) || other.payloadJson == payloadJson)&&const DeepCollectionEquality().equals(other.bodies, _bodies)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,summary,payloadJson,const DeepCollectionEquality().hash(_bodies),occurredAtMs);
}

@override
String toString() {
    return 'BridgeWorkGroupMember.fileChange(id: $id, seq: $seq, summary: $summary, payloadJson: $payloadJson, bodies: $bodies, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeWorkGroupMember_FileChangeCopyWith<$Res> implements $BridgeWorkGroupMemberCopyWith<$Res> {
  factory $BridgeWorkGroupMember_FileChangeCopyWith(BridgeWorkGroupMember_FileChange value, $Res Function(BridgeWorkGroupMember_FileChange) _then) = _$BridgeWorkGroupMember_FileChangeCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String summary, String payloadJson, List<BridgeBodyRef> bodies, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeWorkGroupMember_FileChangeCopyWithImpl<$Res>
    implements $BridgeWorkGroupMember_FileChangeCopyWith<$Res> {
  _$BridgeWorkGroupMember_FileChangeCopyWithImpl(this._self, this._then);

  final BridgeWorkGroupMember_FileChange _self;
  final $Res Function(BridgeWorkGroupMember_FileChange) _then;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? summary = null,Object? payloadJson = null,Object? bodies = null,Object? occurredAtMs = freezed,}) {
  return _then(BridgeWorkGroupMember_FileChange(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,payloadJson: null == payloadJson ? _self.payloadJson : payloadJson // ignore: cast_nullable_to_non_nullable
as String,bodies: null == bodies ? _self._bodies : bodies // ignore: cast_nullable_to_non_nullable
as List<BridgeBodyRef>,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeWorkGroupMember_Skill extends BridgeWorkGroupMember {
  const BridgeWorkGroupMember_Skill({required this.id, required this.seq, required this.name, required this.summary, required this.payloadJson, this.occurredAtMs}): super._();


@override final  String id;
@override final  BigInt seq;
 final  String name;
 final  String summary;
 final  String payloadJson;
 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWorkGroupMember_SkillCopyWith<BridgeWorkGroupMember_Skill> get copyWith => _$BridgeWorkGroupMember_SkillCopyWithImpl<BridgeWorkGroupMember_Skill>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkGroupMember_Skill&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.name, name) || other.name == name)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.payloadJson, payloadJson) || other.payloadJson == payloadJson)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,name,summary,payloadJson,occurredAtMs);
}

@override
String toString() {
    return 'BridgeWorkGroupMember.skill(id: $id, seq: $seq, name: $name, summary: $summary, payloadJson: $payloadJson, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeWorkGroupMember_SkillCopyWith<$Res> implements $BridgeWorkGroupMemberCopyWith<$Res> {
  factory $BridgeWorkGroupMember_SkillCopyWith(BridgeWorkGroupMember_Skill value, $Res Function(BridgeWorkGroupMember_Skill) _then) = _$BridgeWorkGroupMember_SkillCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String name, String summary, String payloadJson, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeWorkGroupMember_SkillCopyWithImpl<$Res>
    implements $BridgeWorkGroupMember_SkillCopyWith<$Res> {
  _$BridgeWorkGroupMember_SkillCopyWithImpl(this._self, this._then);

  final BridgeWorkGroupMember_Skill _self;
  final $Res Function(BridgeWorkGroupMember_Skill) _then;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? name = null,Object? summary = null,Object? payloadJson = null,Object? occurredAtMs = freezed,}) {
  return _then(BridgeWorkGroupMember_Skill(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,payloadJson: null == payloadJson ? _self.payloadJson : payloadJson // ignore: cast_nullable_to_non_nullable
as String,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeWorkGroupMember_Fallback extends BridgeWorkGroupMember {
  const BridgeWorkGroupMember_Fallback({required this.id, required this.seq, required this.eventId, required this.eventKind, required this.reason, this.occurredAtMs}): super._();


@override final  String id;
@override final  BigInt seq;
 final  String eventId;
 final  String eventKind;
 final  String reason;
 final  PlatformInt64? occurredAtMs;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWorkGroupMember_FallbackCopyWith<BridgeWorkGroupMember_Fallback> get copyWith => _$BridgeWorkGroupMember_FallbackCopyWithImpl<BridgeWorkGroupMember_Fallback>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWorkGroupMember_Fallback&&(identical(other.id, id) || other.id == id)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.eventId, eventId) || other.eventId == eventId)&&(identical(other.eventKind, eventKind) || other.eventKind == eventKind)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,seq,eventId,eventKind,reason,occurredAtMs);
}

@override
String toString() {
    return 'BridgeWorkGroupMember.fallback(id: $id, seq: $seq, eventId: $eventId, eventKind: $eventKind, reason: $reason, occurredAtMs: $occurredAtMs)';
}


}

/// @nodoc
abstract mixin class $BridgeWorkGroupMember_FallbackCopyWith<$Res> implements $BridgeWorkGroupMemberCopyWith<$Res> {
  factory $BridgeWorkGroupMember_FallbackCopyWith(BridgeWorkGroupMember_Fallback value, $Res Function(BridgeWorkGroupMember_Fallback) _then) = _$BridgeWorkGroupMember_FallbackCopyWithImpl;
@override @useResult
$Res call({
 String id, BigInt seq, String eventId, String eventKind, String reason, PlatformInt64? occurredAtMs
});




}
/// @nodoc
class _$BridgeWorkGroupMember_FallbackCopyWithImpl<$Res>
    implements $BridgeWorkGroupMember_FallbackCopyWith<$Res> {
  _$BridgeWorkGroupMember_FallbackCopyWithImpl(this._self, this._then);

  final BridgeWorkGroupMember_Fallback _self;
  final $Res Function(BridgeWorkGroupMember_Fallback) _then;

/// Create a copy of BridgeWorkGroupMember
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? seq = null,Object? eventId = null,Object? eventKind = null,Object? reason = null,Object? occurredAtMs = freezed,}) {
  return _then(BridgeWorkGroupMember_Fallback(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,eventId: null == eventId ? _self.eventId : eventId // ignore: cast_nullable_to_non_nullable
as String,eventKind: null == eventKind ? _self.eventKind : eventKind // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,occurredAtMs: freezed == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

// dart format on
