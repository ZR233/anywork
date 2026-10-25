// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bot_audience.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeBotAudienceCanonicalItem {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAudienceCanonicalItem);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotAudienceCanonicalItem()';
}


}

/// @nodoc
class $BridgeBotAudienceCanonicalItemCopyWith<$Res>  {
$BridgeBotAudienceCanonicalItemCopyWith(BridgeBotAudienceCanonicalItem _, $Res Function(BridgeBotAudienceCanonicalItem) __);
}


/// Adds pattern-matching-related methods to [BridgeBotAudienceCanonicalItem].
extension BridgeBotAudienceCanonicalItemPatterns on BridgeBotAudienceCanonicalItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotAudienceCanonicalItem_Present value)?  present,TResult Function( BridgeBotAudienceCanonicalItem_Removed value)?  removed,TResult Function( BridgeBotAudienceCanonicalItem_Unavailable value)?  unavailable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotAudienceCanonicalItem_Present() when present != null:
return present(_that);case BridgeBotAudienceCanonicalItem_Removed() when removed != null:
return removed(_that);case BridgeBotAudienceCanonicalItem_Unavailable() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotAudienceCanonicalItem_Present value)  present,required TResult Function( BridgeBotAudienceCanonicalItem_Removed value)  removed,required TResult Function( BridgeBotAudienceCanonicalItem_Unavailable value)  unavailable,}){
final _that = this;
switch (_that) {
case BridgeBotAudienceCanonicalItem_Present():
return present(_that);case BridgeBotAudienceCanonicalItem_Removed():
return removed(_that);case BridgeBotAudienceCanonicalItem_Unavailable():
return unavailable(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotAudienceCanonicalItem_Present value)?  present,TResult? Function( BridgeBotAudienceCanonicalItem_Removed value)?  removed,TResult? Function( BridgeBotAudienceCanonicalItem_Unavailable value)?  unavailable,}){
final _that = this;
switch (_that) {
case BridgeBotAudienceCanonicalItem_Present() when present != null:
return present(_that);case BridgeBotAudienceCanonicalItem_Removed() when removed != null:
return removed(_that);case BridgeBotAudienceCanonicalItem_Unavailable() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt revision,  bool saved,  BridgeBotItemEligibility eligibility)?  present,TResult Function()?  removed,TResult Function( BridgeBotCanonicalUnavailableReason reason)?  unavailable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotAudienceCanonicalItem_Present() when present != null:
return present(_that.revision,_that.saved,_that.eligibility);case BridgeBotAudienceCanonicalItem_Removed() when removed != null:
return removed();case BridgeBotAudienceCanonicalItem_Unavailable() when unavailable != null:
return unavailable(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt revision,  bool saved,  BridgeBotItemEligibility eligibility)  present,required TResult Function()  removed,required TResult Function( BridgeBotCanonicalUnavailableReason reason)  unavailable,}) {final _that = this;
switch (_that) {
case BridgeBotAudienceCanonicalItem_Present():
return present(_that.revision,_that.saved,_that.eligibility);case BridgeBotAudienceCanonicalItem_Removed():
return removed();case BridgeBotAudienceCanonicalItem_Unavailable():
return unavailable(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt revision,  bool saved,  BridgeBotItemEligibility eligibility)?  present,TResult? Function()?  removed,TResult? Function( BridgeBotCanonicalUnavailableReason reason)?  unavailable,}) {final _that = this;
switch (_that) {
case BridgeBotAudienceCanonicalItem_Present() when present != null:
return present(_that.revision,_that.saved,_that.eligibility);case BridgeBotAudienceCanonicalItem_Removed() when removed != null:
return removed();case BridgeBotAudienceCanonicalItem_Unavailable() when unavailable != null:
return unavailable(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotAudienceCanonicalItem_Present extends BridgeBotAudienceCanonicalItem {
  const BridgeBotAudienceCanonicalItem_Present({required this.revision, required this.saved, required this.eligibility}): super._();


 final  BigInt revision;
 final  bool saved;
 final  BridgeBotItemEligibility eligibility;

/// Create a copy of BridgeBotAudienceCanonicalItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotAudienceCanonicalItem_PresentCopyWith<BridgeBotAudienceCanonicalItem_Present> get copyWith => _$BridgeBotAudienceCanonicalItem_PresentCopyWithImpl<BridgeBotAudienceCanonicalItem_Present>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAudienceCanonicalItem_Present&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.saved, saved) || other.saved == saved)&&(identical(other.eligibility, eligibility) || other.eligibility == eligibility));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,saved,eligibility);
}

@override
String toString() {
    return 'BridgeBotAudienceCanonicalItem.present(revision: $revision, saved: $saved, eligibility: $eligibility)';
}


}

/// @nodoc
abstract mixin class $BridgeBotAudienceCanonicalItem_PresentCopyWith<$Res> implements $BridgeBotAudienceCanonicalItemCopyWith<$Res> {
  factory $BridgeBotAudienceCanonicalItem_PresentCopyWith(BridgeBotAudienceCanonicalItem_Present value, $Res Function(BridgeBotAudienceCanonicalItem_Present) _then) = _$BridgeBotAudienceCanonicalItem_PresentCopyWithImpl;
@useResult
$Res call({
 BigInt revision, bool saved, BridgeBotItemEligibility eligibility
});


$BridgeBotItemEligibilityCopyWith<$Res> get eligibility;

}
/// @nodoc
class _$BridgeBotAudienceCanonicalItem_PresentCopyWithImpl<$Res>
    implements $BridgeBotAudienceCanonicalItem_PresentCopyWith<$Res> {
  _$BridgeBotAudienceCanonicalItem_PresentCopyWithImpl(this._self, this._then);

  final BridgeBotAudienceCanonicalItem_Present _self;
  final $Res Function(BridgeBotAudienceCanonicalItem_Present) _then;

/// Create a copy of BridgeBotAudienceCanonicalItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? saved = null,Object? eligibility = null,}) {
  return _then(BridgeBotAudienceCanonicalItem_Present(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,eligibility: null == eligibility ? _self.eligibility : eligibility // ignore: cast_nullable_to_non_nullable
as BridgeBotItemEligibility,
  ));
}

/// Create a copy of BridgeBotAudienceCanonicalItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeBotItemEligibilityCopyWith<$Res> get eligibility {

  return $BridgeBotItemEligibilityCopyWith<$Res>(_self.eligibility, (value) {
    return _then(_self.copyWith(eligibility: value));
  });
}
}

/// @nodoc


class BridgeBotAudienceCanonicalItem_Removed extends BridgeBotAudienceCanonicalItem {
  const BridgeBotAudienceCanonicalItem_Removed(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAudienceCanonicalItem_Removed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotAudienceCanonicalItem.removed()';
}


}




/// @nodoc


class BridgeBotAudienceCanonicalItem_Unavailable extends BridgeBotAudienceCanonicalItem {
  const BridgeBotAudienceCanonicalItem_Unavailable({required this.reason}): super._();


 final  BridgeBotCanonicalUnavailableReason reason;

/// Create a copy of BridgeBotAudienceCanonicalItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotAudienceCanonicalItem_UnavailableCopyWith<BridgeBotAudienceCanonicalItem_Unavailable> get copyWith => _$BridgeBotAudienceCanonicalItem_UnavailableCopyWithImpl<BridgeBotAudienceCanonicalItem_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAudienceCanonicalItem_Unavailable&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'BridgeBotAudienceCanonicalItem.unavailable(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeBotAudienceCanonicalItem_UnavailableCopyWith<$Res> implements $BridgeBotAudienceCanonicalItemCopyWith<$Res> {
  factory $BridgeBotAudienceCanonicalItem_UnavailableCopyWith(BridgeBotAudienceCanonicalItem_Unavailable value, $Res Function(BridgeBotAudienceCanonicalItem_Unavailable) _then) = _$BridgeBotAudienceCanonicalItem_UnavailableCopyWithImpl;
@useResult
$Res call({
 BridgeBotCanonicalUnavailableReason reason
});




}
/// @nodoc
class _$BridgeBotAudienceCanonicalItem_UnavailableCopyWithImpl<$Res>
    implements $BridgeBotAudienceCanonicalItem_UnavailableCopyWith<$Res> {
  _$BridgeBotAudienceCanonicalItem_UnavailableCopyWithImpl(this._self, this._then);

  final BridgeBotAudienceCanonicalItem_Unavailable _self;
  final $Res Function(BridgeBotAudienceCanonicalItem_Unavailable) _then;

/// Create a copy of BridgeBotAudienceCanonicalItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeBotAudienceCanonicalItem_Unavailable(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeBotCanonicalUnavailableReason,
  ));
}


}

/// @nodoc
mixin _$BridgeBotAudienceItemsRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAudienceItemsRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotAudienceItemsRead()';
}


}

/// @nodoc
class $BridgeBotAudienceItemsReadCopyWith<$Res>  {
$BridgeBotAudienceItemsReadCopyWith(BridgeBotAudienceItemsRead _, $Res Function(BridgeBotAudienceItemsRead) __);
}


/// Adds pattern-matching-related methods to [BridgeBotAudienceItemsRead].
extension BridgeBotAudienceItemsReadPatterns on BridgeBotAudienceItemsRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotAudienceItemsRead_Unavailable value)?  unavailable,TResult Function( BridgeBotAudienceItemsRead_Items value)?  items,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotAudienceItemsRead_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeBotAudienceItemsRead_Items() when items != null:
return items(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotAudienceItemsRead_Unavailable value)  unavailable,required TResult Function( BridgeBotAudienceItemsRead_Items value)  items,}){
final _that = this;
switch (_that) {
case BridgeBotAudienceItemsRead_Unavailable():
return unavailable(_that);case BridgeBotAudienceItemsRead_Items():
return items(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotAudienceItemsRead_Unavailable value)?  unavailable,TResult? Function( BridgeBotAudienceItemsRead_Items value)?  items,}){
final _that = this;
switch (_that) {
case BridgeBotAudienceItemsRead_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeBotAudienceItemsRead_Items() when items != null:
return items(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeBotAudienceItemsUnavailableReason reason)?  unavailable,TResult Function( BridgeBotAuthorizationRef authorization,  BridgeBotAuthorizationPhase phase,  BigInt summaryVersion,  BigInt deliveryVersion,  List<BridgeBotAudienceItemStatus> items)?  items,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotAudienceItemsRead_Unavailable() when unavailable != null:
return unavailable(_that.reason);case BridgeBotAudienceItemsRead_Items() when items != null:
return items(_that.authorization,_that.phase,_that.summaryVersion,_that.deliveryVersion,_that.items);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeBotAudienceItemsUnavailableReason reason)  unavailable,required TResult Function( BridgeBotAuthorizationRef authorization,  BridgeBotAuthorizationPhase phase,  BigInt summaryVersion,  BigInt deliveryVersion,  List<BridgeBotAudienceItemStatus> items)  items,}) {final _that = this;
switch (_that) {
case BridgeBotAudienceItemsRead_Unavailable():
return unavailable(_that.reason);case BridgeBotAudienceItemsRead_Items():
return items(_that.authorization,_that.phase,_that.summaryVersion,_that.deliveryVersion,_that.items);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeBotAudienceItemsUnavailableReason reason)?  unavailable,TResult? Function( BridgeBotAuthorizationRef authorization,  BridgeBotAuthorizationPhase phase,  BigInt summaryVersion,  BigInt deliveryVersion,  List<BridgeBotAudienceItemStatus> items)?  items,}) {final _that = this;
switch (_that) {
case BridgeBotAudienceItemsRead_Unavailable() when unavailable != null:
return unavailable(_that.reason);case BridgeBotAudienceItemsRead_Items() when items != null:
return items(_that.authorization,_that.phase,_that.summaryVersion,_that.deliveryVersion,_that.items);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotAudienceItemsRead_Unavailable extends BridgeBotAudienceItemsRead {
  const BridgeBotAudienceItemsRead_Unavailable({required this.reason}): super._();


 final  BridgeBotAudienceItemsUnavailableReason reason;

/// Create a copy of BridgeBotAudienceItemsRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotAudienceItemsRead_UnavailableCopyWith<BridgeBotAudienceItemsRead_Unavailable> get copyWith => _$BridgeBotAudienceItemsRead_UnavailableCopyWithImpl<BridgeBotAudienceItemsRead_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAudienceItemsRead_Unavailable&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'BridgeBotAudienceItemsRead.unavailable(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeBotAudienceItemsRead_UnavailableCopyWith<$Res> implements $BridgeBotAudienceItemsReadCopyWith<$Res> {
  factory $BridgeBotAudienceItemsRead_UnavailableCopyWith(BridgeBotAudienceItemsRead_Unavailable value, $Res Function(BridgeBotAudienceItemsRead_Unavailable) _then) = _$BridgeBotAudienceItemsRead_UnavailableCopyWithImpl;
@useResult
$Res call({
 BridgeBotAudienceItemsUnavailableReason reason
});




}
/// @nodoc
class _$BridgeBotAudienceItemsRead_UnavailableCopyWithImpl<$Res>
    implements $BridgeBotAudienceItemsRead_UnavailableCopyWith<$Res> {
  _$BridgeBotAudienceItemsRead_UnavailableCopyWithImpl(this._self, this._then);

  final BridgeBotAudienceItemsRead_Unavailable _self;
  final $Res Function(BridgeBotAudienceItemsRead_Unavailable) _then;

/// Create a copy of BridgeBotAudienceItemsRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeBotAudienceItemsRead_Unavailable(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeBotAudienceItemsUnavailableReason,
  ));
}


}

/// @nodoc


class BridgeBotAudienceItemsRead_Items extends BridgeBotAudienceItemsRead {
  const BridgeBotAudienceItemsRead_Items({required this.authorization, required this.phase, required this.summaryVersion, required this.deliveryVersion, required  List<BridgeBotAudienceItemStatus> items}): _items = items,super._();


 final  BridgeBotAuthorizationRef authorization;
 final  BridgeBotAuthorizationPhase phase;
 final  BigInt summaryVersion;
 final  BigInt deliveryVersion;
 final  List<BridgeBotAudienceItemStatus> _items;
 List<BridgeBotAudienceItemStatus> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}


/// Create a copy of BridgeBotAudienceItemsRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotAudienceItemsRead_ItemsCopyWith<BridgeBotAudienceItemsRead_Items> get copyWith => _$BridgeBotAudienceItemsRead_ItemsCopyWithImpl<BridgeBotAudienceItemsRead_Items>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAudienceItemsRead_Items&&(identical(other.authorization, authorization) || other.authorization == authorization)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.summaryVersion, summaryVersion) || other.summaryVersion == summaryVersion)&&(identical(other.deliveryVersion, deliveryVersion) || other.deliveryVersion == deliveryVersion)&&const DeepCollectionEquality().equals(other.items, _items));
}


@override
int get hashCode {
    return Object.hash(runtimeType,authorization,phase,summaryVersion,deliveryVersion,const DeepCollectionEquality().hash(_items));
}

@override
String toString() {
    return 'BridgeBotAudienceItemsRead.items(authorization: $authorization, phase: $phase, summaryVersion: $summaryVersion, deliveryVersion: $deliveryVersion, items: $items)';
}


}

/// @nodoc
abstract mixin class $BridgeBotAudienceItemsRead_ItemsCopyWith<$Res> implements $BridgeBotAudienceItemsReadCopyWith<$Res> {
  factory $BridgeBotAudienceItemsRead_ItemsCopyWith(BridgeBotAudienceItemsRead_Items value, $Res Function(BridgeBotAudienceItemsRead_Items) _then) = _$BridgeBotAudienceItemsRead_ItemsCopyWithImpl;
@useResult
$Res call({
 BridgeBotAuthorizationRef authorization, BridgeBotAuthorizationPhase phase, BigInt summaryVersion, BigInt deliveryVersion, List<BridgeBotAudienceItemStatus> items
});




}
/// @nodoc
class _$BridgeBotAudienceItemsRead_ItemsCopyWithImpl<$Res>
    implements $BridgeBotAudienceItemsRead_ItemsCopyWith<$Res> {
  _$BridgeBotAudienceItemsRead_ItemsCopyWithImpl(this._self, this._then);

  final BridgeBotAudienceItemsRead_Items _self;
  final $Res Function(BridgeBotAudienceItemsRead_Items) _then;

/// Create a copy of BridgeBotAudienceItemsRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? authorization = null,Object? phase = null,Object? summaryVersion = null,Object? deliveryVersion = null,Object? items = null,}) {
  return _then(BridgeBotAudienceItemsRead_Items(
authorization: null == authorization ? _self.authorization : authorization // ignore: cast_nullable_to_non_nullable
as BridgeBotAuthorizationRef,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as BridgeBotAuthorizationPhase,summaryVersion: null == summaryVersion ? _self.summaryVersion : summaryVersion // ignore: cast_nullable_to_non_nullable
as BigInt,deliveryVersion: null == deliveryVersion ? _self.deliveryVersion : deliveryVersion // ignore: cast_nullable_to_non_nullable
as BigInt,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<BridgeBotAudienceItemStatus>,
  ));
}


}

/// @nodoc
mixin _$BridgeBotItemDelivery {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemDelivery);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotItemDelivery()';
}


}

/// @nodoc
class $BridgeBotItemDeliveryCopyWith<$Res>  {
$BridgeBotItemDeliveryCopyWith(BridgeBotItemDelivery _, $Res Function(BridgeBotItemDelivery) __);
}


/// Adds pattern-matching-related methods to [BridgeBotItemDelivery].
extension BridgeBotItemDeliveryPatterns on BridgeBotItemDelivery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotItemDelivery_NotProjected value)?  notProjected,TResult Function( BridgeBotItemDelivery_Known value)?  known,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotItemDelivery_NotProjected() when notProjected != null:
return notProjected(_that);case BridgeBotItemDelivery_Known() when known != null:
return known(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotItemDelivery_NotProjected value)  notProjected,required TResult Function( BridgeBotItemDelivery_Known value)  known,}){
final _that = this;
switch (_that) {
case BridgeBotItemDelivery_NotProjected():
return notProjected(_that);case BridgeBotItemDelivery_Known():
return known(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotItemDelivery_NotProjected value)?  notProjected,TResult? Function( BridgeBotItemDelivery_Known value)?  known,}){
final _that = this;
switch (_that) {
case BridgeBotItemDelivery_NotProjected() when notProjected != null:
return notProjected(_that);case BridgeBotItemDelivery_Known() when known != null:
return known(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notProjected,TResult Function( BridgeBotItemLedgerSummary ledger)?  known,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotItemDelivery_NotProjected() when notProjected != null:
return notProjected();case BridgeBotItemDelivery_Known() when known != null:
return known(_that.ledger);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notProjected,required TResult Function( BridgeBotItemLedgerSummary ledger)  known,}) {final _that = this;
switch (_that) {
case BridgeBotItemDelivery_NotProjected():
return notProjected();case BridgeBotItemDelivery_Known():
return known(_that.ledger);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notProjected,TResult? Function( BridgeBotItemLedgerSummary ledger)?  known,}) {final _that = this;
switch (_that) {
case BridgeBotItemDelivery_NotProjected() when notProjected != null:
return notProjected();case BridgeBotItemDelivery_Known() when known != null:
return known(_that.ledger);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotItemDelivery_NotProjected extends BridgeBotItemDelivery {
  const BridgeBotItemDelivery_NotProjected(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemDelivery_NotProjected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotItemDelivery.notProjected()';
}


}




/// @nodoc


class BridgeBotItemDelivery_Known extends BridgeBotItemDelivery {
  const BridgeBotItemDelivery_Known({required this.ledger}): super._();


 final  BridgeBotItemLedgerSummary ledger;

/// Create a copy of BridgeBotItemDelivery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotItemDelivery_KnownCopyWith<BridgeBotItemDelivery_Known> get copyWith => _$BridgeBotItemDelivery_KnownCopyWithImpl<BridgeBotItemDelivery_Known>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemDelivery_Known&&(identical(other.ledger, ledger) || other.ledger == ledger));
}


@override
int get hashCode {
    return Object.hash(runtimeType,ledger);
}

@override
String toString() {
    return 'BridgeBotItemDelivery.known(ledger: $ledger)';
}


}

/// @nodoc
abstract mixin class $BridgeBotItemDelivery_KnownCopyWith<$Res> implements $BridgeBotItemDeliveryCopyWith<$Res> {
  factory $BridgeBotItemDelivery_KnownCopyWith(BridgeBotItemDelivery_Known value, $Res Function(BridgeBotItemDelivery_Known) _then) = _$BridgeBotItemDelivery_KnownCopyWithImpl;
@useResult
$Res call({
 BridgeBotItemLedgerSummary ledger
});




}
/// @nodoc
class _$BridgeBotItemDelivery_KnownCopyWithImpl<$Res>
    implements $BridgeBotItemDelivery_KnownCopyWith<$Res> {
  _$BridgeBotItemDelivery_KnownCopyWithImpl(this._self, this._then);

  final BridgeBotItemDelivery_Known _self;
  final $Res Function(BridgeBotItemDelivery_Known) _then;

/// Create a copy of BridgeBotItemDelivery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ledger = null,}) {
  return _then(BridgeBotItemDelivery_Known(
ledger: null == ledger ? _self.ledger : ledger // ignore: cast_nullable_to_non_nullable
as BridgeBotItemLedgerSummary,
  ));
}


}

/// @nodoc
mixin _$BridgeBotItemEligibility {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemEligibility);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotItemEligibility()';
}


}

/// @nodoc
class $BridgeBotItemEligibilityCopyWith<$Res>  {
$BridgeBotItemEligibilityCopyWith(BridgeBotItemEligibility _, $Res Function(BridgeBotItemEligibility) __);
}


/// Adds pattern-matching-related methods to [BridgeBotItemEligibility].
extension BridgeBotItemEligibilityPatterns on BridgeBotItemEligibility {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotItemEligibility_Text value)?  text,TResult Function( BridgeBotItemEligibility_PublicArtifact value)?  publicArtifact,TResult Function( BridgeBotItemEligibility_NotAuthorized value)?  notAuthorized,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotItemEligibility_Text() when text != null:
return text(_that);case BridgeBotItemEligibility_PublicArtifact() when publicArtifact != null:
return publicArtifact(_that);case BridgeBotItemEligibility_NotAuthorized() when notAuthorized != null:
return notAuthorized(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotItemEligibility_Text value)  text,required TResult Function( BridgeBotItemEligibility_PublicArtifact value)  publicArtifact,required TResult Function( BridgeBotItemEligibility_NotAuthorized value)  notAuthorized,}){
final _that = this;
switch (_that) {
case BridgeBotItemEligibility_Text():
return text(_that);case BridgeBotItemEligibility_PublicArtifact():
return publicArtifact(_that);case BridgeBotItemEligibility_NotAuthorized():
return notAuthorized(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotItemEligibility_Text value)?  text,TResult? Function( BridgeBotItemEligibility_PublicArtifact value)?  publicArtifact,TResult? Function( BridgeBotItemEligibility_NotAuthorized value)?  notAuthorized,}){
final _that = this;
switch (_that) {
case BridgeBotItemEligibility_Text() when text != null:
return text(_that);case BridgeBotItemEligibility_PublicArtifact() when publicArtifact != null:
return publicArtifact(_that);case BridgeBotItemEligibility_NotAuthorized() when notAuthorized != null:
return notAuthorized(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeBotPublicTextChannel channel)?  text,TResult Function()?  publicArtifact,TResult Function( BridgeBotItemExclusion reason)?  notAuthorized,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotItemEligibility_Text() when text != null:
return text(_that.channel);case BridgeBotItemEligibility_PublicArtifact() when publicArtifact != null:
return publicArtifact();case BridgeBotItemEligibility_NotAuthorized() when notAuthorized != null:
return notAuthorized(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeBotPublicTextChannel channel)  text,required TResult Function()  publicArtifact,required TResult Function( BridgeBotItemExclusion reason)  notAuthorized,}) {final _that = this;
switch (_that) {
case BridgeBotItemEligibility_Text():
return text(_that.channel);case BridgeBotItemEligibility_PublicArtifact():
return publicArtifact();case BridgeBotItemEligibility_NotAuthorized():
return notAuthorized(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeBotPublicTextChannel channel)?  text,TResult? Function()?  publicArtifact,TResult? Function( BridgeBotItemExclusion reason)?  notAuthorized,}) {final _that = this;
switch (_that) {
case BridgeBotItemEligibility_Text() when text != null:
return text(_that.channel);case BridgeBotItemEligibility_PublicArtifact() when publicArtifact != null:
return publicArtifact();case BridgeBotItemEligibility_NotAuthorized() when notAuthorized != null:
return notAuthorized(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotItemEligibility_Text extends BridgeBotItemEligibility {
  const BridgeBotItemEligibility_Text({required this.channel}): super._();


 final  BridgeBotPublicTextChannel channel;

/// Create a copy of BridgeBotItemEligibility
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotItemEligibility_TextCopyWith<BridgeBotItemEligibility_Text> get copyWith => _$BridgeBotItemEligibility_TextCopyWithImpl<BridgeBotItemEligibility_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemEligibility_Text&&(identical(other.channel, channel) || other.channel == channel));
}


@override
int get hashCode {
    return Object.hash(runtimeType,channel);
}

@override
String toString() {
    return 'BridgeBotItemEligibility.text(channel: $channel)';
}


}

/// @nodoc
abstract mixin class $BridgeBotItemEligibility_TextCopyWith<$Res> implements $BridgeBotItemEligibilityCopyWith<$Res> {
  factory $BridgeBotItemEligibility_TextCopyWith(BridgeBotItemEligibility_Text value, $Res Function(BridgeBotItemEligibility_Text) _then) = _$BridgeBotItemEligibility_TextCopyWithImpl;
@useResult
$Res call({
 BridgeBotPublicTextChannel channel
});




}
/// @nodoc
class _$BridgeBotItemEligibility_TextCopyWithImpl<$Res>
    implements $BridgeBotItemEligibility_TextCopyWith<$Res> {
  _$BridgeBotItemEligibility_TextCopyWithImpl(this._self, this._then);

  final BridgeBotItemEligibility_Text _self;
  final $Res Function(BridgeBotItemEligibility_Text) _then;

/// Create a copy of BridgeBotItemEligibility
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? channel = null,}) {
  return _then(BridgeBotItemEligibility_Text(
channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as BridgeBotPublicTextChannel,
  ));
}


}

/// @nodoc


class BridgeBotItemEligibility_PublicArtifact extends BridgeBotItemEligibility {
  const BridgeBotItemEligibility_PublicArtifact(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemEligibility_PublicArtifact);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotItemEligibility.publicArtifact()';
}


}




/// @nodoc


class BridgeBotItemEligibility_NotAuthorized extends BridgeBotItemEligibility {
  const BridgeBotItemEligibility_NotAuthorized({required this.reason}): super._();


 final  BridgeBotItemExclusion reason;

/// Create a copy of BridgeBotItemEligibility
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotItemEligibility_NotAuthorizedCopyWith<BridgeBotItemEligibility_NotAuthorized> get copyWith => _$BridgeBotItemEligibility_NotAuthorizedCopyWithImpl<BridgeBotItemEligibility_NotAuthorized>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemEligibility_NotAuthorized&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'BridgeBotItemEligibility.notAuthorized(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeBotItemEligibility_NotAuthorizedCopyWith<$Res> implements $BridgeBotItemEligibilityCopyWith<$Res> {
  factory $BridgeBotItemEligibility_NotAuthorizedCopyWith(BridgeBotItemEligibility_NotAuthorized value, $Res Function(BridgeBotItemEligibility_NotAuthorized) _then) = _$BridgeBotItemEligibility_NotAuthorizedCopyWithImpl;
@useResult
$Res call({
 BridgeBotItemExclusion reason
});




}
/// @nodoc
class _$BridgeBotItemEligibility_NotAuthorizedCopyWithImpl<$Res>
    implements $BridgeBotItemEligibility_NotAuthorizedCopyWith<$Res> {
  _$BridgeBotItemEligibility_NotAuthorizedCopyWithImpl(this._self, this._then);

  final BridgeBotItemEligibility_NotAuthorized _self;
  final $Res Function(BridgeBotItemEligibility_NotAuthorized) _then;

/// Create a copy of BridgeBotItemEligibility
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeBotItemEligibility_NotAuthorized(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeBotItemExclusion,
  ));
}


}

/// @nodoc
mixin _$BridgeBotItemPlatform {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemPlatform);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotItemPlatform()';
}


}

/// @nodoc
class $BridgeBotItemPlatformCopyWith<$Res>  {
$BridgeBotItemPlatformCopyWith(BridgeBotItemPlatform _, $Res Function(BridgeBotItemPlatform) __);
}


/// Adds pattern-matching-related methods to [BridgeBotItemPlatform].
extension BridgeBotItemPlatformPatterns on BridgeBotItemPlatform {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotItemPlatform_None value)?  none,TResult Function( BridgeBotItemPlatform_Blocked value)?  blocked,TResult Function( BridgeBotItemPlatform_Card value)?  card,TResult Function( BridgeBotItemPlatform_File value)?  file,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotItemPlatform_None() when none != null:
return none(_that);case BridgeBotItemPlatform_Blocked() when blocked != null:
return blocked(_that);case BridgeBotItemPlatform_Card() when card != null:
return card(_that);case BridgeBotItemPlatform_File() when file != null:
return file(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotItemPlatform_None value)  none,required TResult Function( BridgeBotItemPlatform_Blocked value)  blocked,required TResult Function( BridgeBotItemPlatform_Card value)  card,required TResult Function( BridgeBotItemPlatform_File value)  file,}){
final _that = this;
switch (_that) {
case BridgeBotItemPlatform_None():
return none(_that);case BridgeBotItemPlatform_Blocked():
return blocked(_that);case BridgeBotItemPlatform_Card():
return card(_that);case BridgeBotItemPlatform_File():
return file(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotItemPlatform_None value)?  none,TResult? Function( BridgeBotItemPlatform_Blocked value)?  blocked,TResult? Function( BridgeBotItemPlatform_Card value)?  card,TResult? Function( BridgeBotItemPlatform_File value)?  file,}){
final _that = this;
switch (_that) {
case BridgeBotItemPlatform_None() when none != null:
return none(_that);case BridgeBotItemPlatform_Blocked() when blocked != null:
return blocked(_that);case BridgeBotItemPlatform_Card() when card != null:
return card(_that);case BridgeBotItemPlatform_File() when file != null:
return file(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  none,TResult Function( BridgeBotFileBlockReason reason)?  blocked,TResult Function( BridgeBotCardOperationSummary latestOperation)?  card,TResult Function( String operationId,  BigInt contentRevision,  BridgeBotPlatformResult upload,  BridgeBotPlatformResult message,  BridgeBotFileOutcome outcome,  BridgeBotSendStopReason? localStop)?  file,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotItemPlatform_None() when none != null:
return none();case BridgeBotItemPlatform_Blocked() when blocked != null:
return blocked(_that.reason);case BridgeBotItemPlatform_Card() when card != null:
return card(_that.latestOperation);case BridgeBotItemPlatform_File() when file != null:
return file(_that.operationId,_that.contentRevision,_that.upload,_that.message,_that.outcome,_that.localStop);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  none,required TResult Function( BridgeBotFileBlockReason reason)  blocked,required TResult Function( BridgeBotCardOperationSummary latestOperation)  card,required TResult Function( String operationId,  BigInt contentRevision,  BridgeBotPlatformResult upload,  BridgeBotPlatformResult message,  BridgeBotFileOutcome outcome,  BridgeBotSendStopReason? localStop)  file,}) {final _that = this;
switch (_that) {
case BridgeBotItemPlatform_None():
return none();case BridgeBotItemPlatform_Blocked():
return blocked(_that.reason);case BridgeBotItemPlatform_Card():
return card(_that.latestOperation);case BridgeBotItemPlatform_File():
return file(_that.operationId,_that.contentRevision,_that.upload,_that.message,_that.outcome,_that.localStop);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  none,TResult? Function( BridgeBotFileBlockReason reason)?  blocked,TResult? Function( BridgeBotCardOperationSummary latestOperation)?  card,TResult? Function( String operationId,  BigInt contentRevision,  BridgeBotPlatformResult upload,  BridgeBotPlatformResult message,  BridgeBotFileOutcome outcome,  BridgeBotSendStopReason? localStop)?  file,}) {final _that = this;
switch (_that) {
case BridgeBotItemPlatform_None() when none != null:
return none();case BridgeBotItemPlatform_Blocked() when blocked != null:
return blocked(_that.reason);case BridgeBotItemPlatform_Card() when card != null:
return card(_that.latestOperation);case BridgeBotItemPlatform_File() when file != null:
return file(_that.operationId,_that.contentRevision,_that.upload,_that.message,_that.outcome,_that.localStop);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotItemPlatform_None extends BridgeBotItemPlatform {
  const BridgeBotItemPlatform_None(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemPlatform_None);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotItemPlatform.none()';
}


}




/// @nodoc


class BridgeBotItemPlatform_Blocked extends BridgeBotItemPlatform {
  const BridgeBotItemPlatform_Blocked({required this.reason}): super._();


 final  BridgeBotFileBlockReason reason;

/// Create a copy of BridgeBotItemPlatform
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotItemPlatform_BlockedCopyWith<BridgeBotItemPlatform_Blocked> get copyWith => _$BridgeBotItemPlatform_BlockedCopyWithImpl<BridgeBotItemPlatform_Blocked>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemPlatform_Blocked&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'BridgeBotItemPlatform.blocked(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeBotItemPlatform_BlockedCopyWith<$Res> implements $BridgeBotItemPlatformCopyWith<$Res> {
  factory $BridgeBotItemPlatform_BlockedCopyWith(BridgeBotItemPlatform_Blocked value, $Res Function(BridgeBotItemPlatform_Blocked) _then) = _$BridgeBotItemPlatform_BlockedCopyWithImpl;
@useResult
$Res call({
 BridgeBotFileBlockReason reason
});




}
/// @nodoc
class _$BridgeBotItemPlatform_BlockedCopyWithImpl<$Res>
    implements $BridgeBotItemPlatform_BlockedCopyWith<$Res> {
  _$BridgeBotItemPlatform_BlockedCopyWithImpl(this._self, this._then);

  final BridgeBotItemPlatform_Blocked _self;
  final $Res Function(BridgeBotItemPlatform_Blocked) _then;

/// Create a copy of BridgeBotItemPlatform
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeBotItemPlatform_Blocked(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeBotFileBlockReason,
  ));
}


}

/// @nodoc


class BridgeBotItemPlatform_Card extends BridgeBotItemPlatform {
  const BridgeBotItemPlatform_Card({required this.latestOperation}): super._();


 final  BridgeBotCardOperationSummary latestOperation;

/// Create a copy of BridgeBotItemPlatform
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotItemPlatform_CardCopyWith<BridgeBotItemPlatform_Card> get copyWith => _$BridgeBotItemPlatform_CardCopyWithImpl<BridgeBotItemPlatform_Card>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemPlatform_Card&&(identical(other.latestOperation, latestOperation) || other.latestOperation == latestOperation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,latestOperation);
}

@override
String toString() {
    return 'BridgeBotItemPlatform.card(latestOperation: $latestOperation)';
}


}

/// @nodoc
abstract mixin class $BridgeBotItemPlatform_CardCopyWith<$Res> implements $BridgeBotItemPlatformCopyWith<$Res> {
  factory $BridgeBotItemPlatform_CardCopyWith(BridgeBotItemPlatform_Card value, $Res Function(BridgeBotItemPlatform_Card) _then) = _$BridgeBotItemPlatform_CardCopyWithImpl;
@useResult
$Res call({
 BridgeBotCardOperationSummary latestOperation
});




}
/// @nodoc
class _$BridgeBotItemPlatform_CardCopyWithImpl<$Res>
    implements $BridgeBotItemPlatform_CardCopyWith<$Res> {
  _$BridgeBotItemPlatform_CardCopyWithImpl(this._self, this._then);

  final BridgeBotItemPlatform_Card _self;
  final $Res Function(BridgeBotItemPlatform_Card) _then;

/// Create a copy of BridgeBotItemPlatform
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? latestOperation = null,}) {
  return _then(BridgeBotItemPlatform_Card(
latestOperation: null == latestOperation ? _self.latestOperation : latestOperation // ignore: cast_nullable_to_non_nullable
as BridgeBotCardOperationSummary,
  ));
}


}

/// @nodoc


class BridgeBotItemPlatform_File extends BridgeBotItemPlatform {
  const BridgeBotItemPlatform_File({required this.operationId, required this.contentRevision, required this.upload, required this.message, required this.outcome, this.localStop}): super._();


 final  String operationId;
 final  BigInt contentRevision;
 final  BridgeBotPlatformResult upload;
 final  BridgeBotPlatformResult message;
 final  BridgeBotFileOutcome outcome;
 final  BridgeBotSendStopReason? localStop;

/// Create a copy of BridgeBotItemPlatform
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotItemPlatform_FileCopyWith<BridgeBotItemPlatform_File> get copyWith => _$BridgeBotItemPlatform_FileCopyWithImpl<BridgeBotItemPlatform_File>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemPlatform_File&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.contentRevision, contentRevision) || other.contentRevision == contentRevision)&&(identical(other.upload, upload) || other.upload == upload)&&(identical(other.message, message) || other.message == message)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.localStop, localStop) || other.localStop == localStop));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,contentRevision,upload,message,outcome,localStop);
}

@override
String toString() {
    return 'BridgeBotItemPlatform.file(operationId: $operationId, contentRevision: $contentRevision, upload: $upload, message: $message, outcome: $outcome, localStop: $localStop)';
}


}

/// @nodoc
abstract mixin class $BridgeBotItemPlatform_FileCopyWith<$Res> implements $BridgeBotItemPlatformCopyWith<$Res> {
  factory $BridgeBotItemPlatform_FileCopyWith(BridgeBotItemPlatform_File value, $Res Function(BridgeBotItemPlatform_File) _then) = _$BridgeBotItemPlatform_FileCopyWithImpl;
@useResult
$Res call({
 String operationId, BigInt contentRevision, BridgeBotPlatformResult upload, BridgeBotPlatformResult message, BridgeBotFileOutcome outcome, BridgeBotSendStopReason? localStop
});


$BridgeBotPlatformResultCopyWith<$Res> get upload;$BridgeBotPlatformResultCopyWith<$Res> get message;

}
/// @nodoc
class _$BridgeBotItemPlatform_FileCopyWithImpl<$Res>
    implements $BridgeBotItemPlatform_FileCopyWith<$Res> {
  _$BridgeBotItemPlatform_FileCopyWithImpl(this._self, this._then);

  final BridgeBotItemPlatform_File _self;
  final $Res Function(BridgeBotItemPlatform_File) _then;

/// Create a copy of BridgeBotItemPlatform
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? contentRevision = null,Object? upload = null,Object? message = null,Object? outcome = null,Object? localStop = freezed,}) {
  return _then(BridgeBotItemPlatform_File(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,contentRevision: null == contentRevision ? _self.contentRevision : contentRevision // ignore: cast_nullable_to_non_nullable
as BigInt,upload: null == upload ? _self.upload : upload // ignore: cast_nullable_to_non_nullable
as BridgeBotPlatformResult,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as BridgeBotPlatformResult,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as BridgeBotFileOutcome,localStop: freezed == localStop ? _self.localStop : localStop // ignore: cast_nullable_to_non_nullable
as BridgeBotSendStopReason?,
  ));
}

/// Create a copy of BridgeBotItemPlatform
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeBotPlatformResultCopyWith<$Res> get upload {

  return $BridgeBotPlatformResultCopyWith<$Res>(_self.upload, (value) {
    return _then(_self.copyWith(upload: value));
  });
}/// Create a copy of BridgeBotItemPlatform
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeBotPlatformResultCopyWith<$Res> get message {

  return $BridgeBotPlatformResultCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc
mixin _$BridgeBotItemPresentation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemPresentation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotItemPresentation()';
}


}

/// @nodoc
class $BridgeBotItemPresentationCopyWith<$Res>  {
$BridgeBotItemPresentationCopyWith(BridgeBotItemPresentation _, $Res Function(BridgeBotItemPresentation) __);
}


/// Adds pattern-matching-related methods to [BridgeBotItemPresentation].
extension BridgeBotItemPresentationPatterns on BridgeBotItemPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotItemPresentation_None value)?  none,TResult Function( BridgeBotItemPresentation_Text value)?  text,TResult Function( BridgeBotItemPresentation_File value)?  file,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotItemPresentation_None() when none != null:
return none(_that);case BridgeBotItemPresentation_Text() when text != null:
return text(_that);case BridgeBotItemPresentation_File() when file != null:
return file(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotItemPresentation_None value)  none,required TResult Function( BridgeBotItemPresentation_Text value)  text,required TResult Function( BridgeBotItemPresentation_File value)  file,}){
final _that = this;
switch (_that) {
case BridgeBotItemPresentation_None():
return none(_that);case BridgeBotItemPresentation_Text():
return text(_that);case BridgeBotItemPresentation_File():
return file(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotItemPresentation_None value)?  none,TResult? Function( BridgeBotItemPresentation_Text value)?  text,TResult? Function( BridgeBotItemPresentation_File value)?  file,}){
final _that = this;
switch (_that) {
case BridgeBotItemPresentation_None() when none != null:
return none(_that);case BridgeBotItemPresentation_Text() when text != null:
return text(_that);case BridgeBotItemPresentation_File() when file != null:
return file(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  none,TResult Function( BigInt revision,  BridgeBotTextIntegrity integrity,  bool saved)?  text,TResult Function( BigInt revision)?  file,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotItemPresentation_None() when none != null:
return none();case BridgeBotItemPresentation_Text() when text != null:
return text(_that.revision,_that.integrity,_that.saved);case BridgeBotItemPresentation_File() when file != null:
return file(_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  none,required TResult Function( BigInt revision,  BridgeBotTextIntegrity integrity,  bool saved)  text,required TResult Function( BigInt revision)  file,}) {final _that = this;
switch (_that) {
case BridgeBotItemPresentation_None():
return none();case BridgeBotItemPresentation_Text():
return text(_that.revision,_that.integrity,_that.saved);case BridgeBotItemPresentation_File():
return file(_that.revision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  none,TResult? Function( BigInt revision,  BridgeBotTextIntegrity integrity,  bool saved)?  text,TResult? Function( BigInt revision)?  file,}) {final _that = this;
switch (_that) {
case BridgeBotItemPresentation_None() when none != null:
return none();case BridgeBotItemPresentation_Text() when text != null:
return text(_that.revision,_that.integrity,_that.saved);case BridgeBotItemPresentation_File() when file != null:
return file(_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotItemPresentation_None extends BridgeBotItemPresentation {
  const BridgeBotItemPresentation_None(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemPresentation_None);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotItemPresentation.none()';
}


}




/// @nodoc


class BridgeBotItemPresentation_Text extends BridgeBotItemPresentation {
  const BridgeBotItemPresentation_Text({required this.revision, required this.integrity, required this.saved}): super._();


 final  BigInt revision;
 final  BridgeBotTextIntegrity integrity;
 final  bool saved;

/// Create a copy of BridgeBotItemPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotItemPresentation_TextCopyWith<BridgeBotItemPresentation_Text> get copyWith => _$BridgeBotItemPresentation_TextCopyWithImpl<BridgeBotItemPresentation_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemPresentation_Text&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.integrity, integrity) || other.integrity == integrity)&&(identical(other.saved, saved) || other.saved == saved));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,integrity,saved);
}

@override
String toString() {
    return 'BridgeBotItemPresentation.text(revision: $revision, integrity: $integrity, saved: $saved)';
}


}

/// @nodoc
abstract mixin class $BridgeBotItemPresentation_TextCopyWith<$Res> implements $BridgeBotItemPresentationCopyWith<$Res> {
  factory $BridgeBotItemPresentation_TextCopyWith(BridgeBotItemPresentation_Text value, $Res Function(BridgeBotItemPresentation_Text) _then) = _$BridgeBotItemPresentation_TextCopyWithImpl;
@useResult
$Res call({
 BigInt revision, BridgeBotTextIntegrity integrity, bool saved
});




}
/// @nodoc
class _$BridgeBotItemPresentation_TextCopyWithImpl<$Res>
    implements $BridgeBotItemPresentation_TextCopyWith<$Res> {
  _$BridgeBotItemPresentation_TextCopyWithImpl(this._self, this._then);

  final BridgeBotItemPresentation_Text _self;
  final $Res Function(BridgeBotItemPresentation_Text) _then;

/// Create a copy of BridgeBotItemPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? integrity = null,Object? saved = null,}) {
  return _then(BridgeBotItemPresentation_Text(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,integrity: null == integrity ? _self.integrity : integrity // ignore: cast_nullable_to_non_nullable
as BridgeBotTextIntegrity,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeBotItemPresentation_File extends BridgeBotItemPresentation {
  const BridgeBotItemPresentation_File({required this.revision}): super._();


 final  BigInt revision;

/// Create a copy of BridgeBotItemPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotItemPresentation_FileCopyWith<BridgeBotItemPresentation_File> get copyWith => _$BridgeBotItemPresentation_FileCopyWithImpl<BridgeBotItemPresentation_File>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotItemPresentation_File&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision);
}

@override
String toString() {
    return 'BridgeBotItemPresentation.file(revision: $revision)';
}


}

/// @nodoc
abstract mixin class $BridgeBotItemPresentation_FileCopyWith<$Res> implements $BridgeBotItemPresentationCopyWith<$Res> {
  factory $BridgeBotItemPresentation_FileCopyWith(BridgeBotItemPresentation_File value, $Res Function(BridgeBotItemPresentation_File) _then) = _$BridgeBotItemPresentation_FileCopyWithImpl;
@useResult
$Res call({
 BigInt revision
});




}
/// @nodoc
class _$BridgeBotItemPresentation_FileCopyWithImpl<$Res>
    implements $BridgeBotItemPresentation_FileCopyWith<$Res> {
  _$BridgeBotItemPresentation_FileCopyWithImpl(this._self, this._then);

  final BridgeBotItemPresentation_File _self;
  final $Res Function(BridgeBotItemPresentation_File) _then;

/// Create a copy of BridgeBotItemPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? revision = null,}) {
  return _then(BridgeBotItemPresentation_File(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc
mixin _$BridgeBotPlatformResult {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotPlatformResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotPlatformResult()';
}


}

/// @nodoc
class $BridgeBotPlatformResultCopyWith<$Res>  {
$BridgeBotPlatformResultCopyWith(BridgeBotPlatformResult _, $Res Function(BridgeBotPlatformResult) __);
}


/// Adds pattern-matching-related methods to [BridgeBotPlatformResult].
extension BridgeBotPlatformResultPatterns on BridgeBotPlatformResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotPlatformResult_NotStarted value)?  notStarted,TResult Function( BridgeBotPlatformResult_InFlight value)?  inFlight,TResult Function( BridgeBotPlatformResult_Accepted value)?  accepted,TResult Function( BridgeBotPlatformResult_Rejected value)?  rejected,TResult Function( BridgeBotPlatformResult_Unknown value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotPlatformResult_NotStarted() when notStarted != null:
return notStarted(_that);case BridgeBotPlatformResult_InFlight() when inFlight != null:
return inFlight(_that);case BridgeBotPlatformResult_Accepted() when accepted != null:
return accepted(_that);case BridgeBotPlatformResult_Rejected() when rejected != null:
return rejected(_that);case BridgeBotPlatformResult_Unknown() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotPlatformResult_NotStarted value)  notStarted,required TResult Function( BridgeBotPlatformResult_InFlight value)  inFlight,required TResult Function( BridgeBotPlatformResult_Accepted value)  accepted,required TResult Function( BridgeBotPlatformResult_Rejected value)  rejected,required TResult Function( BridgeBotPlatformResult_Unknown value)  unknown,}){
final _that = this;
switch (_that) {
case BridgeBotPlatformResult_NotStarted():
return notStarted(_that);case BridgeBotPlatformResult_InFlight():
return inFlight(_that);case BridgeBotPlatformResult_Accepted():
return accepted(_that);case BridgeBotPlatformResult_Rejected():
return rejected(_that);case BridgeBotPlatformResult_Unknown():
return unknown(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotPlatformResult_NotStarted value)?  notStarted,TResult? Function( BridgeBotPlatformResult_InFlight value)?  inFlight,TResult? Function( BridgeBotPlatformResult_Accepted value)?  accepted,TResult? Function( BridgeBotPlatformResult_Rejected value)?  rejected,TResult? Function( BridgeBotPlatformResult_Unknown value)?  unknown,}){
final _that = this;
switch (_that) {
case BridgeBotPlatformResult_NotStarted() when notStarted != null:
return notStarted(_that);case BridgeBotPlatformResult_InFlight() when inFlight != null:
return inFlight(_that);case BridgeBotPlatformResult_Accepted() when accepted != null:
return accepted(_that);case BridgeBotPlatformResult_Rejected() when rejected != null:
return rejected(_that);case BridgeBotPlatformResult_Unknown() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notStarted,TResult Function()?  inFlight,TResult Function()?  accepted,TResult Function( BridgeBotDiagnostic diagnostic)?  rejected,TResult Function( BridgeBotDiagnostic diagnostic)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotPlatformResult_NotStarted() when notStarted != null:
return notStarted();case BridgeBotPlatformResult_InFlight() when inFlight != null:
return inFlight();case BridgeBotPlatformResult_Accepted() when accepted != null:
return accepted();case BridgeBotPlatformResult_Rejected() when rejected != null:
return rejected(_that.diagnostic);case BridgeBotPlatformResult_Unknown() when unknown != null:
return unknown(_that.diagnostic);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notStarted,required TResult Function()  inFlight,required TResult Function()  accepted,required TResult Function( BridgeBotDiagnostic diagnostic)  rejected,required TResult Function( BridgeBotDiagnostic diagnostic)  unknown,}) {final _that = this;
switch (_that) {
case BridgeBotPlatformResult_NotStarted():
return notStarted();case BridgeBotPlatformResult_InFlight():
return inFlight();case BridgeBotPlatformResult_Accepted():
return accepted();case BridgeBotPlatformResult_Rejected():
return rejected(_that.diagnostic);case BridgeBotPlatformResult_Unknown():
return unknown(_that.diagnostic);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notStarted,TResult? Function()?  inFlight,TResult? Function()?  accepted,TResult? Function( BridgeBotDiagnostic diagnostic)?  rejected,TResult? Function( BridgeBotDiagnostic diagnostic)?  unknown,}) {final _that = this;
switch (_that) {
case BridgeBotPlatformResult_NotStarted() when notStarted != null:
return notStarted();case BridgeBotPlatformResult_InFlight() when inFlight != null:
return inFlight();case BridgeBotPlatformResult_Accepted() when accepted != null:
return accepted();case BridgeBotPlatformResult_Rejected() when rejected != null:
return rejected(_that.diagnostic);case BridgeBotPlatformResult_Unknown() when unknown != null:
return unknown(_that.diagnostic);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotPlatformResult_NotStarted extends BridgeBotPlatformResult {
  const BridgeBotPlatformResult_NotStarted(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotPlatformResult_NotStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotPlatformResult.notStarted()';
}


}




/// @nodoc


class BridgeBotPlatformResult_InFlight extends BridgeBotPlatformResult {
  const BridgeBotPlatformResult_InFlight(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotPlatformResult_InFlight);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotPlatformResult.inFlight()';
}


}




/// @nodoc


class BridgeBotPlatformResult_Accepted extends BridgeBotPlatformResult {
  const BridgeBotPlatformResult_Accepted(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotPlatformResult_Accepted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotPlatformResult.accepted()';
}


}




/// @nodoc


class BridgeBotPlatformResult_Rejected extends BridgeBotPlatformResult {
  const BridgeBotPlatformResult_Rejected({required this.diagnostic}): super._();


 final  BridgeBotDiagnostic diagnostic;

/// Create a copy of BridgeBotPlatformResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotPlatformResult_RejectedCopyWith<BridgeBotPlatformResult_Rejected> get copyWith => _$BridgeBotPlatformResult_RejectedCopyWithImpl<BridgeBotPlatformResult_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotPlatformResult_Rejected&&(identical(other.diagnostic, diagnostic) || other.diagnostic == diagnostic));
}


@override
int get hashCode {
    return Object.hash(runtimeType,diagnostic);
}

@override
String toString() {
    return 'BridgeBotPlatformResult.rejected(diagnostic: $diagnostic)';
}


}

/// @nodoc
abstract mixin class $BridgeBotPlatformResult_RejectedCopyWith<$Res> implements $BridgeBotPlatformResultCopyWith<$Res> {
  factory $BridgeBotPlatformResult_RejectedCopyWith(BridgeBotPlatformResult_Rejected value, $Res Function(BridgeBotPlatformResult_Rejected) _then) = _$BridgeBotPlatformResult_RejectedCopyWithImpl;
@useResult
$Res call({
 BridgeBotDiagnostic diagnostic
});




}
/// @nodoc
class _$BridgeBotPlatformResult_RejectedCopyWithImpl<$Res>
    implements $BridgeBotPlatformResult_RejectedCopyWith<$Res> {
  _$BridgeBotPlatformResult_RejectedCopyWithImpl(this._self, this._then);

  final BridgeBotPlatformResult_Rejected _self;
  final $Res Function(BridgeBotPlatformResult_Rejected) _then;

/// Create a copy of BridgeBotPlatformResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? diagnostic = null,}) {
  return _then(BridgeBotPlatformResult_Rejected(
diagnostic: null == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as BridgeBotDiagnostic,
  ));
}


}

/// @nodoc


class BridgeBotPlatformResult_Unknown extends BridgeBotPlatformResult {
  const BridgeBotPlatformResult_Unknown({required this.diagnostic}): super._();


 final  BridgeBotDiagnostic diagnostic;

/// Create a copy of BridgeBotPlatformResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotPlatformResult_UnknownCopyWith<BridgeBotPlatformResult_Unknown> get copyWith => _$BridgeBotPlatformResult_UnknownCopyWithImpl<BridgeBotPlatformResult_Unknown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotPlatformResult_Unknown&&(identical(other.diagnostic, diagnostic) || other.diagnostic == diagnostic));
}


@override
int get hashCode {
    return Object.hash(runtimeType,diagnostic);
}

@override
String toString() {
    return 'BridgeBotPlatformResult.unknown(diagnostic: $diagnostic)';
}


}

/// @nodoc
abstract mixin class $BridgeBotPlatformResult_UnknownCopyWith<$Res> implements $BridgeBotPlatformResultCopyWith<$Res> {
  factory $BridgeBotPlatformResult_UnknownCopyWith(BridgeBotPlatformResult_Unknown value, $Res Function(BridgeBotPlatformResult_Unknown) _then) = _$BridgeBotPlatformResult_UnknownCopyWithImpl;
@useResult
$Res call({
 BridgeBotDiagnostic diagnostic
});




}
/// @nodoc
class _$BridgeBotPlatformResult_UnknownCopyWithImpl<$Res>
    implements $BridgeBotPlatformResult_UnknownCopyWith<$Res> {
  _$BridgeBotPlatformResult_UnknownCopyWithImpl(this._self, this._then);

  final BridgeBotPlatformResult_Unknown _self;
  final $Res Function(BridgeBotPlatformResult_Unknown) _then;

/// Create a copy of BridgeBotPlatformResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? diagnostic = null,}) {
  return _then(BridgeBotPlatformResult_Unknown(
diagnostic: null == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as BridgeBotDiagnostic,
  ));
}


}

/// @nodoc
mixin _$BridgeBotThreadSyncCommandState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotThreadSyncCommandState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotThreadSyncCommandState()';
}


}

/// @nodoc
class $BridgeBotThreadSyncCommandStateCopyWith<$Res>  {
$BridgeBotThreadSyncCommandStateCopyWith(BridgeBotThreadSyncCommandState _, $Res Function(BridgeBotThreadSyncCommandState) __);
}


/// Adds pattern-matching-related methods to [BridgeBotThreadSyncCommandState].
extension BridgeBotThreadSyncCommandStatePatterns on BridgeBotThreadSyncCommandState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotThreadSyncCommandState_Settled value)?  settled,TResult Function( BridgeBotThreadSyncCommandState_PendingStart value)?  pendingStart,TResult Function( BridgeBotThreadSyncCommandState_Superseded value)?  superseded,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotThreadSyncCommandState_Settled() when settled != null:
return settled(_that);case BridgeBotThreadSyncCommandState_PendingStart() when pendingStart != null:
return pendingStart(_that);case BridgeBotThreadSyncCommandState_Superseded() when superseded != null:
return superseded(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotThreadSyncCommandState_Settled value)  settled,required TResult Function( BridgeBotThreadSyncCommandState_PendingStart value)  pendingStart,required TResult Function( BridgeBotThreadSyncCommandState_Superseded value)  superseded,}){
final _that = this;
switch (_that) {
case BridgeBotThreadSyncCommandState_Settled():
return settled(_that);case BridgeBotThreadSyncCommandState_PendingStart():
return pendingStart(_that);case BridgeBotThreadSyncCommandState_Superseded():
return superseded(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotThreadSyncCommandState_Settled value)?  settled,TResult? Function( BridgeBotThreadSyncCommandState_PendingStart value)?  pendingStart,TResult? Function( BridgeBotThreadSyncCommandState_Superseded value)?  superseded,}){
final _that = this;
switch (_that) {
case BridgeBotThreadSyncCommandState_Settled() when settled != null:
return settled(_that);case BridgeBotThreadSyncCommandState_PendingStart() when pendingStart != null:
return pendingStart(_that);case BridgeBotThreadSyncCommandState_Superseded() when superseded != null:
return superseded(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  settled,TResult Function( BridgeBotAuthorizationId authorization)?  pendingStart,TResult Function( BridgeBotAuthorizationId authorization)?  superseded,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotThreadSyncCommandState_Settled() when settled != null:
return settled();case BridgeBotThreadSyncCommandState_PendingStart() when pendingStart != null:
return pendingStart(_that.authorization);case BridgeBotThreadSyncCommandState_Superseded() when superseded != null:
return superseded(_that.authorization);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  settled,required TResult Function( BridgeBotAuthorizationId authorization)  pendingStart,required TResult Function( BridgeBotAuthorizationId authorization)  superseded,}) {final _that = this;
switch (_that) {
case BridgeBotThreadSyncCommandState_Settled():
return settled();case BridgeBotThreadSyncCommandState_PendingStart():
return pendingStart(_that.authorization);case BridgeBotThreadSyncCommandState_Superseded():
return superseded(_that.authorization);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  settled,TResult? Function( BridgeBotAuthorizationId authorization)?  pendingStart,TResult? Function( BridgeBotAuthorizationId authorization)?  superseded,}) {final _that = this;
switch (_that) {
case BridgeBotThreadSyncCommandState_Settled() when settled != null:
return settled();case BridgeBotThreadSyncCommandState_PendingStart() when pendingStart != null:
return pendingStart(_that.authorization);case BridgeBotThreadSyncCommandState_Superseded() when superseded != null:
return superseded(_that.authorization);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotThreadSyncCommandState_Settled extends BridgeBotThreadSyncCommandState {
  const BridgeBotThreadSyncCommandState_Settled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotThreadSyncCommandState_Settled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotThreadSyncCommandState.settled()';
}


}




/// @nodoc


class BridgeBotThreadSyncCommandState_PendingStart extends BridgeBotThreadSyncCommandState {
  const BridgeBotThreadSyncCommandState_PendingStart({required this.authorization}): super._();


 final  BridgeBotAuthorizationId authorization;

/// Create a copy of BridgeBotThreadSyncCommandState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotThreadSyncCommandState_PendingStartCopyWith<BridgeBotThreadSyncCommandState_PendingStart> get copyWith => _$BridgeBotThreadSyncCommandState_PendingStartCopyWithImpl<BridgeBotThreadSyncCommandState_PendingStart>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotThreadSyncCommandState_PendingStart&&(identical(other.authorization, authorization) || other.authorization == authorization));
}


@override
int get hashCode {
    return Object.hash(runtimeType,authorization);
}

@override
String toString() {
    return 'BridgeBotThreadSyncCommandState.pendingStart(authorization: $authorization)';
}


}

/// @nodoc
abstract mixin class $BridgeBotThreadSyncCommandState_PendingStartCopyWith<$Res> implements $BridgeBotThreadSyncCommandStateCopyWith<$Res> {
  factory $BridgeBotThreadSyncCommandState_PendingStartCopyWith(BridgeBotThreadSyncCommandState_PendingStart value, $Res Function(BridgeBotThreadSyncCommandState_PendingStart) _then) = _$BridgeBotThreadSyncCommandState_PendingStartCopyWithImpl;
@useResult
$Res call({
 BridgeBotAuthorizationId authorization
});




}
/// @nodoc
class _$BridgeBotThreadSyncCommandState_PendingStartCopyWithImpl<$Res>
    implements $BridgeBotThreadSyncCommandState_PendingStartCopyWith<$Res> {
  _$BridgeBotThreadSyncCommandState_PendingStartCopyWithImpl(this._self, this._then);

  final BridgeBotThreadSyncCommandState_PendingStart _self;
  final $Res Function(BridgeBotThreadSyncCommandState_PendingStart) _then;

/// Create a copy of BridgeBotThreadSyncCommandState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? authorization = null,}) {
  return _then(BridgeBotThreadSyncCommandState_PendingStart(
authorization: null == authorization ? _self.authorization : authorization // ignore: cast_nullable_to_non_nullable
as BridgeBotAuthorizationId,
  ));
}


}

/// @nodoc


class BridgeBotThreadSyncCommandState_Superseded extends BridgeBotThreadSyncCommandState {
  const BridgeBotThreadSyncCommandState_Superseded({required this.authorization}): super._();


 final  BridgeBotAuthorizationId authorization;

/// Create a copy of BridgeBotThreadSyncCommandState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotThreadSyncCommandState_SupersededCopyWith<BridgeBotThreadSyncCommandState_Superseded> get copyWith => _$BridgeBotThreadSyncCommandState_SupersededCopyWithImpl<BridgeBotThreadSyncCommandState_Superseded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotThreadSyncCommandState_Superseded&&(identical(other.authorization, authorization) || other.authorization == authorization));
}


@override
int get hashCode {
    return Object.hash(runtimeType,authorization);
}

@override
String toString() {
    return 'BridgeBotThreadSyncCommandState.superseded(authorization: $authorization)';
}


}

/// @nodoc
abstract mixin class $BridgeBotThreadSyncCommandState_SupersededCopyWith<$Res> implements $BridgeBotThreadSyncCommandStateCopyWith<$Res> {
  factory $BridgeBotThreadSyncCommandState_SupersededCopyWith(BridgeBotThreadSyncCommandState_Superseded value, $Res Function(BridgeBotThreadSyncCommandState_Superseded) _then) = _$BridgeBotThreadSyncCommandState_SupersededCopyWithImpl;
@useResult
$Res call({
 BridgeBotAuthorizationId authorization
});




}
/// @nodoc
class _$BridgeBotThreadSyncCommandState_SupersededCopyWithImpl<$Res>
    implements $BridgeBotThreadSyncCommandState_SupersededCopyWith<$Res> {
  _$BridgeBotThreadSyncCommandState_SupersededCopyWithImpl(this._self, this._then);

  final BridgeBotThreadSyncCommandState_Superseded _self;
  final $Res Function(BridgeBotThreadSyncCommandState_Superseded) _then;

/// Create a copy of BridgeBotThreadSyncCommandState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? authorization = null,}) {
  return _then(BridgeBotThreadSyncCommandState_Superseded(
authorization: null == authorization ? _self.authorization : authorization // ignore: cast_nullable_to_non_nullable
as BridgeBotAuthorizationId,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadClosedAuthorizationsRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadClosedAuthorizationsRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadClosedAuthorizationsRead()';
}


}

/// @nodoc
class $BridgeThreadClosedAuthorizationsReadCopyWith<$Res>  {
$BridgeThreadClosedAuthorizationsReadCopyWith(BridgeThreadClosedAuthorizationsRead _, $Res Function(BridgeThreadClosedAuthorizationsRead) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadClosedAuthorizationsRead].
extension BridgeThreadClosedAuthorizationsReadPatterns on BridgeThreadClosedAuthorizationsRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadClosedAuthorizationsRead_Unbound value)?  unbound,TResult Function( BridgeThreadClosedAuthorizationsRead_Unavailable value)?  unavailable,TResult Function( BridgeThreadClosedAuthorizationsRead_Page value)?  page,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadClosedAuthorizationsRead_Unbound() when unbound != null:
return unbound(_that);case BridgeThreadClosedAuthorizationsRead_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeThreadClosedAuthorizationsRead_Page() when page != null:
return page(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadClosedAuthorizationsRead_Unbound value)  unbound,required TResult Function( BridgeThreadClosedAuthorizationsRead_Unavailable value)  unavailable,required TResult Function( BridgeThreadClosedAuthorizationsRead_Page value)  page,}){
final _that = this;
switch (_that) {
case BridgeThreadClosedAuthorizationsRead_Unbound():
return unbound(_that);case BridgeThreadClosedAuthorizationsRead_Unavailable():
return unavailable(_that);case BridgeThreadClosedAuthorizationsRead_Page():
return page(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadClosedAuthorizationsRead_Unbound value)?  unbound,TResult? Function( BridgeThreadClosedAuthorizationsRead_Unavailable value)?  unavailable,TResult? Function( BridgeThreadClosedAuthorizationsRead_Page value)?  page,}){
final _that = this;
switch (_that) {
case BridgeThreadClosedAuthorizationsRead_Unbound() when unbound != null:
return unbound(_that);case BridgeThreadClosedAuthorizationsRead_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeThreadClosedAuthorizationsRead_Page() when page != null:
return page(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unbound,TResult Function( BridgeThreadAudienceUnavailableReason reason)?  unavailable,TResult Function( BridgeThreadClosedAuthorizationPage page)?  page,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadClosedAuthorizationsRead_Unbound() when unbound != null:
return unbound();case BridgeThreadClosedAuthorizationsRead_Unavailable() when unavailable != null:
return unavailable(_that.reason);case BridgeThreadClosedAuthorizationsRead_Page() when page != null:
return page(_that.page);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unbound,required TResult Function( BridgeThreadAudienceUnavailableReason reason)  unavailable,required TResult Function( BridgeThreadClosedAuthorizationPage page)  page,}) {final _that = this;
switch (_that) {
case BridgeThreadClosedAuthorizationsRead_Unbound():
return unbound();case BridgeThreadClosedAuthorizationsRead_Unavailable():
return unavailable(_that.reason);case BridgeThreadClosedAuthorizationsRead_Page():
return page(_that.page);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unbound,TResult? Function( BridgeThreadAudienceUnavailableReason reason)?  unavailable,TResult? Function( BridgeThreadClosedAuthorizationPage page)?  page,}) {final _that = this;
switch (_that) {
case BridgeThreadClosedAuthorizationsRead_Unbound() when unbound != null:
return unbound();case BridgeThreadClosedAuthorizationsRead_Unavailable() when unavailable != null:
return unavailable(_that.reason);case BridgeThreadClosedAuthorizationsRead_Page() when page != null:
return page(_that.page);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadClosedAuthorizationsRead_Unbound extends BridgeThreadClosedAuthorizationsRead {
  const BridgeThreadClosedAuthorizationsRead_Unbound(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadClosedAuthorizationsRead_Unbound);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadClosedAuthorizationsRead.unbound()';
}


}




/// @nodoc


class BridgeThreadClosedAuthorizationsRead_Unavailable extends BridgeThreadClosedAuthorizationsRead {
  const BridgeThreadClosedAuthorizationsRead_Unavailable({required this.reason}): super._();


 final  BridgeThreadAudienceUnavailableReason reason;

/// Create a copy of BridgeThreadClosedAuthorizationsRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadClosedAuthorizationsRead_UnavailableCopyWith<BridgeThreadClosedAuthorizationsRead_Unavailable> get copyWith => _$BridgeThreadClosedAuthorizationsRead_UnavailableCopyWithImpl<BridgeThreadClosedAuthorizationsRead_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadClosedAuthorizationsRead_Unavailable&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'BridgeThreadClosedAuthorizationsRead.unavailable(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadClosedAuthorizationsRead_UnavailableCopyWith<$Res> implements $BridgeThreadClosedAuthorizationsReadCopyWith<$Res> {
  factory $BridgeThreadClosedAuthorizationsRead_UnavailableCopyWith(BridgeThreadClosedAuthorizationsRead_Unavailable value, $Res Function(BridgeThreadClosedAuthorizationsRead_Unavailable) _then) = _$BridgeThreadClosedAuthorizationsRead_UnavailableCopyWithImpl;
@useResult
$Res call({
 BridgeThreadAudienceUnavailableReason reason
});




}
/// @nodoc
class _$BridgeThreadClosedAuthorizationsRead_UnavailableCopyWithImpl<$Res>
    implements $BridgeThreadClosedAuthorizationsRead_UnavailableCopyWith<$Res> {
  _$BridgeThreadClosedAuthorizationsRead_UnavailableCopyWithImpl(this._self, this._then);

  final BridgeThreadClosedAuthorizationsRead_Unavailable _self;
  final $Res Function(BridgeThreadClosedAuthorizationsRead_Unavailable) _then;

/// Create a copy of BridgeThreadClosedAuthorizationsRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeThreadClosedAuthorizationsRead_Unavailable(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeThreadAudienceUnavailableReason,
  ));
}


}

/// @nodoc


class BridgeThreadClosedAuthorizationsRead_Page extends BridgeThreadClosedAuthorizationsRead {
  const BridgeThreadClosedAuthorizationsRead_Page({required this.page}): super._();


 final  BridgeThreadClosedAuthorizationPage page;

/// Create a copy of BridgeThreadClosedAuthorizationsRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadClosedAuthorizationsRead_PageCopyWith<BridgeThreadClosedAuthorizationsRead_Page> get copyWith => _$BridgeThreadClosedAuthorizationsRead_PageCopyWithImpl<BridgeThreadClosedAuthorizationsRead_Page>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadClosedAuthorizationsRead_Page&&(identical(other.page, page) || other.page == page));
}


@override
int get hashCode {
    return Object.hash(runtimeType,page);
}

@override
String toString() {
    return 'BridgeThreadClosedAuthorizationsRead.page(page: $page)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadClosedAuthorizationsRead_PageCopyWith<$Res> implements $BridgeThreadClosedAuthorizationsReadCopyWith<$Res> {
  factory $BridgeThreadClosedAuthorizationsRead_PageCopyWith(BridgeThreadClosedAuthorizationsRead_Page value, $Res Function(BridgeThreadClosedAuthorizationsRead_Page) _then) = _$BridgeThreadClosedAuthorizationsRead_PageCopyWithImpl;
@useResult
$Res call({
 BridgeThreadClosedAuthorizationPage page
});




}
/// @nodoc
class _$BridgeThreadClosedAuthorizationsRead_PageCopyWithImpl<$Res>
    implements $BridgeThreadClosedAuthorizationsRead_PageCopyWith<$Res> {
  _$BridgeThreadClosedAuthorizationsRead_PageCopyWithImpl(this._self, this._then);

  final BridgeThreadClosedAuthorizationsRead_Page _self;
  final $Res Function(BridgeThreadClosedAuthorizationsRead_Page) _then;

/// Create a copy of BridgeThreadClosedAuthorizationsRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? page = null,}) {
  return _then(BridgeThreadClosedAuthorizationsRead_Page(
page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as BridgeThreadClosedAuthorizationPage,
  ));
}


}

// dart format on
