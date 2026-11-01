// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeChatScope {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatScope);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeChatScope()';
}


}

/// @nodoc
class $BridgeChatScopeCopyWith<$Res>  {
$BridgeChatScopeCopyWith(BridgeChatScope _, $Res Function(BridgeChatScope) __);
}


/// Adds pattern-matching-related methods to [BridgeChatScope].
extension BridgeChatScopePatterns on BridgeChatScope {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeChatScope_Main value)?  main,TResult Function( BridgeChatScope_Children value)?  children,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeChatScope_Main() when main != null:
return main(_that);case BridgeChatScope_Children() when children != null:
return children(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeChatScope_Main value)  main,required TResult Function( BridgeChatScope_Children value)  children,}){
final _that = this;
switch (_that) {
case BridgeChatScope_Main():
return main(_that);case BridgeChatScope_Children():
return children(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeChatScope_Main value)?  main,TResult? Function( BridgeChatScope_Children value)?  children,}){
final _that = this;
switch (_that) {
case BridgeChatScope_Main() when main != null:
return main(_that);case BridgeChatScope_Children() when children != null:
return children(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  main,TResult Function( String parentId)?  children,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeChatScope_Main() when main != null:
return main();case BridgeChatScope_Children() when children != null:
return children(_that.parentId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  main,required TResult Function( String parentId)  children,}) {final _that = this;
switch (_that) {
case BridgeChatScope_Main():
return main();case BridgeChatScope_Children():
return children(_that.parentId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  main,TResult? Function( String parentId)?  children,}) {final _that = this;
switch (_that) {
case BridgeChatScope_Main() when main != null:
return main();case BridgeChatScope_Children() when children != null:
return children(_that.parentId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeChatScope_Main extends BridgeChatScope {
  const BridgeChatScope_Main(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatScope_Main);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeChatScope.main()';
}


}




/// @nodoc


class BridgeChatScope_Children extends BridgeChatScope {
  const BridgeChatScope_Children({required this.parentId}): super._();


 final  String parentId;

/// Create a copy of BridgeChatScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatScope_ChildrenCopyWith<BridgeChatScope_Children> get copyWith => _$BridgeChatScope_ChildrenCopyWithImpl<BridgeChatScope_Children>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatScope_Children&&(identical(other.parentId, parentId) || other.parentId == parentId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,parentId);
}

@override
String toString() {
    return 'BridgeChatScope.children(parentId: $parentId)';
}


}

/// @nodoc
abstract mixin class $BridgeChatScope_ChildrenCopyWith<$Res> implements $BridgeChatScopeCopyWith<$Res> {
  factory $BridgeChatScope_ChildrenCopyWith(BridgeChatScope_Children value, $Res Function(BridgeChatScope_Children) _then) = _$BridgeChatScope_ChildrenCopyWithImpl;
@useResult
$Res call({
 String parentId
});




}
/// @nodoc
class _$BridgeChatScope_ChildrenCopyWithImpl<$Res>
    implements $BridgeChatScope_ChildrenCopyWith<$Res> {
  _$BridgeChatScope_ChildrenCopyWithImpl(this._self, this._then);

  final BridgeChatScope_Children _self;
  final $Res Function(BridgeChatScope_Children) _then;

/// Create a copy of BridgeChatScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? parentId = null,}) {
  return _then(BridgeChatScope_Children(
parentId: null == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeContentOwner {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentOwner);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContentOwner()';
}


}

/// @nodoc
class $BridgeContentOwnerCopyWith<$Res>  {
$BridgeContentOwnerCopyWith(BridgeContentOwner _, $Res Function(BridgeContentOwner) __);
}


/// Adds pattern-matching-related methods to [BridgeContentOwner].
extension BridgeContentOwnerPatterns on BridgeContentOwner {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeContentOwner_Item value)?  item,TResult Function( BridgeContentOwner_Current value)?  current,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeContentOwner_Item() when item != null:
return item(_that);case BridgeContentOwner_Current() when current != null:
return current(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeContentOwner_Item value)  item,required TResult Function( BridgeContentOwner_Current value)  current,}){
final _that = this;
switch (_that) {
case BridgeContentOwner_Item():
return item(_that);case BridgeContentOwner_Current():
return current(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeContentOwner_Item value)?  item,TResult? Function( BridgeContentOwner_Current value)?  current,}){
final _that = this;
switch (_that) {
case BridgeContentOwner_Item() when item != null:
return item(_that);case BridgeContentOwner_Current() when current != null:
return current(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String itemId)?  item,TResult Function( String domain,  String id,  BigInt revision)?  current,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeContentOwner_Item() when item != null:
return item(_that.itemId);case BridgeContentOwner_Current() when current != null:
return current(_that.domain,_that.id,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String itemId)  item,required TResult Function( String domain,  String id,  BigInt revision)  current,}) {final _that = this;
switch (_that) {
case BridgeContentOwner_Item():
return item(_that.itemId);case BridgeContentOwner_Current():
return current(_that.domain,_that.id,_that.revision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String itemId)?  item,TResult? Function( String domain,  String id,  BigInt revision)?  current,}) {final _that = this;
switch (_that) {
case BridgeContentOwner_Item() when item != null:
return item(_that.itemId);case BridgeContentOwner_Current() when current != null:
return current(_that.domain,_that.id,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class BridgeContentOwner_Item extends BridgeContentOwner {
  const BridgeContentOwner_Item({required this.itemId}): super._();


 final  String itemId;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentOwner_ItemCopyWith<BridgeContentOwner_Item> get copyWith => _$BridgeContentOwner_ItemCopyWithImpl<BridgeContentOwner_Item>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentOwner_Item&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId);
}

@override
String toString() {
    return 'BridgeContentOwner.item(itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $BridgeContentOwner_ItemCopyWith<$Res> implements $BridgeContentOwnerCopyWith<$Res> {
  factory $BridgeContentOwner_ItemCopyWith(BridgeContentOwner_Item value, $Res Function(BridgeContentOwner_Item) _then) = _$BridgeContentOwner_ItemCopyWithImpl;
@useResult
$Res call({
 String itemId
});




}
/// @nodoc
class _$BridgeContentOwner_ItemCopyWithImpl<$Res>
    implements $BridgeContentOwner_ItemCopyWith<$Res> {
  _$BridgeContentOwner_ItemCopyWithImpl(this._self, this._then);

  final BridgeContentOwner_Item _self;
  final $Res Function(BridgeContentOwner_Item) _then;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,}) {
  return _then(BridgeContentOwner_Item(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeContentOwner_Current extends BridgeContentOwner {
  const BridgeContentOwner_Current({required this.domain, required this.id, required this.revision}): super._();


 final  String domain;
 final  String id;
 final  BigInt revision;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentOwner_CurrentCopyWith<BridgeContentOwner_Current> get copyWith => _$BridgeContentOwner_CurrentCopyWithImpl<BridgeContentOwner_Current>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentOwner_Current&&(identical(other.domain, domain) || other.domain == domain)&&(identical(other.id, id) || other.id == id)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,domain,id,revision);
}

@override
String toString() {
    return 'BridgeContentOwner.current(domain: $domain, id: $id, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $BridgeContentOwner_CurrentCopyWith<$Res> implements $BridgeContentOwnerCopyWith<$Res> {
  factory $BridgeContentOwner_CurrentCopyWith(BridgeContentOwner_Current value, $Res Function(BridgeContentOwner_Current) _then) = _$BridgeContentOwner_CurrentCopyWithImpl;
@useResult
$Res call({
 String domain, String id, BigInt revision
});




}
/// @nodoc
class _$BridgeContentOwner_CurrentCopyWithImpl<$Res>
    implements $BridgeContentOwner_CurrentCopyWith<$Res> {
  _$BridgeContentOwner_CurrentCopyWithImpl(this._self, this._then);

  final BridgeContentOwner_Current _self;
  final $Res Function(BridgeContentOwner_Current) _then;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? domain = null,Object? id = null,Object? revision = null,}) {
  return _then(BridgeContentOwner_Current(
domain: null == domain ? _self.domain : domain // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc
mixin _$BridgeContentTarget {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentTarget);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContentTarget()';
}


}

/// @nodoc
class $BridgeContentTargetCopyWith<$Res>  {
$BridgeContentTargetCopyWith(BridgeContentTarget _, $Res Function(BridgeContentTarget) __);
}


/// Adds pattern-matching-related methods to [BridgeContentTarget].
extension BridgeContentTargetPatterns on BridgeContentTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeContentTarget_ItemPayload value)?  itemPayload,TResult Function( BridgeContentTarget_Body value)?  body,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload() when itemPayload != null:
return itemPayload(_that);case BridgeContentTarget_Body() when body != null:
return body(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeContentTarget_ItemPayload value)  itemPayload,required TResult Function( BridgeContentTarget_Body value)  body,}){
final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload():
return itemPayload(_that);case BridgeContentTarget_Body():
return body(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeContentTarget_ItemPayload value)?  itemPayload,TResult? Function( BridgeContentTarget_Body value)?  body,}){
final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload() when itemPayload != null:
return itemPayload(_that);case BridgeContentTarget_Body() when body != null:
return body(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String itemId)?  itemPayload,TResult Function( BridgeContentOwner owner,  String key)?  body,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload() when itemPayload != null:
return itemPayload(_that.itemId);case BridgeContentTarget_Body() when body != null:
return body(_that.owner,_that.key);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String itemId)  itemPayload,required TResult Function( BridgeContentOwner owner,  String key)  body,}) {final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload():
return itemPayload(_that.itemId);case BridgeContentTarget_Body():
return body(_that.owner,_that.key);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String itemId)?  itemPayload,TResult? Function( BridgeContentOwner owner,  String key)?  body,}) {final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload() when itemPayload != null:
return itemPayload(_that.itemId);case BridgeContentTarget_Body() when body != null:
return body(_that.owner,_that.key);case _:
  return null;

}
}

}

/// @nodoc


class BridgeContentTarget_ItemPayload extends BridgeContentTarget {
  const BridgeContentTarget_ItemPayload({required this.itemId}): super._();


 final  String itemId;

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentTarget_ItemPayloadCopyWith<BridgeContentTarget_ItemPayload> get copyWith => _$BridgeContentTarget_ItemPayloadCopyWithImpl<BridgeContentTarget_ItemPayload>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentTarget_ItemPayload&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId);
}

@override
String toString() {
    return 'BridgeContentTarget.itemPayload(itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $BridgeContentTarget_ItemPayloadCopyWith<$Res> implements $BridgeContentTargetCopyWith<$Res> {
  factory $BridgeContentTarget_ItemPayloadCopyWith(BridgeContentTarget_ItemPayload value, $Res Function(BridgeContentTarget_ItemPayload) _then) = _$BridgeContentTarget_ItemPayloadCopyWithImpl;
@useResult
$Res call({
 String itemId
});




}
/// @nodoc
class _$BridgeContentTarget_ItemPayloadCopyWithImpl<$Res>
    implements $BridgeContentTarget_ItemPayloadCopyWith<$Res> {
  _$BridgeContentTarget_ItemPayloadCopyWithImpl(this._self, this._then);

  final BridgeContentTarget_ItemPayload _self;
  final $Res Function(BridgeContentTarget_ItemPayload) _then;

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,}) {
  return _then(BridgeContentTarget_ItemPayload(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeContentTarget_Body extends BridgeContentTarget {
  const BridgeContentTarget_Body({required this.owner, required this.key}): super._();


 final  BridgeContentOwner owner;
 final  String key;

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentTarget_BodyCopyWith<BridgeContentTarget_Body> get copyWith => _$BridgeContentTarget_BodyCopyWithImpl<BridgeContentTarget_Body>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentTarget_Body&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode {
    return Object.hash(runtimeType,owner,key);
}

@override
String toString() {
    return 'BridgeContentTarget.body(owner: $owner, key: $key)';
}


}

/// @nodoc
abstract mixin class $BridgeContentTarget_BodyCopyWith<$Res> implements $BridgeContentTargetCopyWith<$Res> {
  factory $BridgeContentTarget_BodyCopyWith(BridgeContentTarget_Body value, $Res Function(BridgeContentTarget_Body) _then) = _$BridgeContentTarget_BodyCopyWithImpl;
@useResult
$Res call({
 BridgeContentOwner owner, String key
});


$BridgeContentOwnerCopyWith<$Res> get owner;

}
/// @nodoc
class _$BridgeContentTarget_BodyCopyWithImpl<$Res>
    implements $BridgeContentTarget_BodyCopyWith<$Res> {
  _$BridgeContentTarget_BodyCopyWithImpl(this._self, this._then);

  final BridgeContentTarget_Body _self;
  final $Res Function(BridgeContentTarget_Body) _then;

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? owner = null,Object? key = null,}) {
  return _then(BridgeContentTarget_Body(
owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as BridgeContentOwner,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeContentOwnerCopyWith<$Res> get owner {

  return $BridgeContentOwnerCopyWith<$Res>(_self.owner, (value) {
    return _then(_self.copyWith(owner: value));
  });
}
}

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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeConversationEvent_State value)?  state,TResult Function( BridgeConversationEvent_Chat value)?  chat,TResult Function( BridgeConversationEvent_Failure value)?  failure,TResult Function( BridgeConversationEvent_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeConversationEvent_State() when state != null:
return state(_that);case BridgeConversationEvent_Chat() when chat != null:
return chat(_that);case BridgeConversationEvent_Failure() when failure != null:
return failure(_that);case BridgeConversationEvent_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeConversationEvent_State value)  state,required TResult Function( BridgeConversationEvent_Chat value)  chat,required TResult Function( BridgeConversationEvent_Failure value)  failure,required TResult Function( BridgeConversationEvent_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeConversationEvent_State():
return state(_that);case BridgeConversationEvent_Chat():
return chat(_that);case BridgeConversationEvent_Failure():
return failure(_that);case BridgeConversationEvent_Closed():
return closed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeConversationEvent_State value)?  state,TResult? Function( BridgeConversationEvent_Chat value)?  chat,TResult? Function( BridgeConversationEvent_Failure value)?  failure,TResult? Function( BridgeConversationEvent_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeConversationEvent_State() when state != null:
return state(_that);case BridgeConversationEvent_Chat() when chat != null:
return chat(_that);case BridgeConversationEvent_Failure() when failure != null:
return failure(_that);case BridgeConversationEvent_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadSubscriptionUpdate update)?  state,TResult Function( BridgeChatBatch batch)?  chat,TResult Function( BridgeError error)?  failure,TResult Function()?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeConversationEvent_State() when state != null:
return state(_that.update);case BridgeConversationEvent_Chat() when chat != null:
return chat(_that.batch);case BridgeConversationEvent_Failure() when failure != null:
return failure(_that.error);case BridgeConversationEvent_Closed() when closed != null:
return closed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadSubscriptionUpdate update)  state,required TResult Function( BridgeChatBatch batch)  chat,required TResult Function( BridgeError error)  failure,required TResult Function()  closed,}) {final _that = this;
switch (_that) {
case BridgeConversationEvent_State():
return state(_that.update);case BridgeConversationEvent_Chat():
return chat(_that.batch);case BridgeConversationEvent_Failure():
return failure(_that.error);case BridgeConversationEvent_Closed():
return closed();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadSubscriptionUpdate update)?  state,TResult? Function( BridgeChatBatch batch)?  chat,TResult? Function( BridgeError error)?  failure,TResult? Function()?  closed,}) {final _that = this;
switch (_that) {
case BridgeConversationEvent_State() when state != null:
return state(_that.update);case BridgeConversationEvent_Chat() when chat != null:
return chat(_that.batch);case BridgeConversationEvent_Failure() when failure != null:
return failure(_that.error);case BridgeConversationEvent_Closed() when closed != null:
return closed();case _:
  return null;

}
}

}

/// @nodoc


class BridgeConversationEvent_State extends BridgeConversationEvent {
  const BridgeConversationEvent_State({required this.update}): super._();


 final  BridgeThreadSubscriptionUpdate update;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_StateCopyWith<BridgeConversationEvent_State> get copyWith => _$BridgeConversationEvent_StateCopyWithImpl<BridgeConversationEvent_State>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_State&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,update);
}

@override
String toString() {
    return 'BridgeConversationEvent.state(update: $update)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_StateCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_StateCopyWith(BridgeConversationEvent_State value, $Res Function(BridgeConversationEvent_State) _then) = _$BridgeConversationEvent_StateCopyWithImpl;
@useResult
$Res call({
 BridgeThreadSubscriptionUpdate update
});


$BridgeThreadSubscriptionUpdateCopyWith<$Res> get update;

}
/// @nodoc
class _$BridgeConversationEvent_StateCopyWithImpl<$Res>
    implements $BridgeConversationEvent_StateCopyWith<$Res> {
  _$BridgeConversationEvent_StateCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_State _self;
  final $Res Function(BridgeConversationEvent_State) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? update = null,}) {
  return _then(BridgeConversationEvent_State(
update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeThreadSubscriptionUpdate,
  ));
}

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeThreadSubscriptionUpdateCopyWith<$Res> get update {

  return $BridgeThreadSubscriptionUpdateCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class BridgeConversationEvent_Chat extends BridgeConversationEvent {
  const BridgeConversationEvent_Chat({required this.batch}): super._();


 final  BridgeChatBatch batch;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_ChatCopyWith<BridgeConversationEvent_Chat> get copyWith => _$BridgeConversationEvent_ChatCopyWithImpl<BridgeConversationEvent_Chat>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_Chat&&(identical(other.batch, batch) || other.batch == batch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,batch);
}

@override
String toString() {
    return 'BridgeConversationEvent.chat(batch: $batch)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_ChatCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_ChatCopyWith(BridgeConversationEvent_Chat value, $Res Function(BridgeConversationEvent_Chat) _then) = _$BridgeConversationEvent_ChatCopyWithImpl;
@useResult
$Res call({
 BridgeChatBatch batch
});




}
/// @nodoc
class _$BridgeConversationEvent_ChatCopyWithImpl<$Res>
    implements $BridgeConversationEvent_ChatCopyWith<$Res> {
  _$BridgeConversationEvent_ChatCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_Chat _self;
  final $Res Function(BridgeConversationEvent_Chat) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? batch = null,}) {
  return _then(BridgeConversationEvent_Chat(
batch: null == batch ? _self.batch : batch // ignore: cast_nullable_to_non_nullable
as BridgeChatBatch,
  ));
}


}

/// @nodoc


class BridgeConversationEvent_Failure extends BridgeConversationEvent {
  const BridgeConversationEvent_Failure({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_FailureCopyWith<BridgeConversationEvent_Failure> get copyWith => _$BridgeConversationEvent_FailureCopyWithImpl<BridgeConversationEvent_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_Failure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeConversationEvent.failure(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_FailureCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_FailureCopyWith(BridgeConversationEvent_Failure value, $Res Function(BridgeConversationEvent_Failure) _then) = _$BridgeConversationEvent_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeConversationEvent_FailureCopyWithImpl<$Res>
    implements $BridgeConversationEvent_FailureCopyWith<$Res> {
  _$BridgeConversationEvent_FailureCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_Failure _self;
  final $Res Function(BridgeConversationEvent_Failure) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeConversationEvent_Failure(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeConversationEvent_Closed extends BridgeConversationEvent {
  const BridgeConversationEvent_Closed(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_Closed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeConversationEvent.closed()';
}


}




/// @nodoc
mixin _$BridgePayloadData {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePayloadData);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgePayloadData()';
}


}

/// @nodoc
class $BridgePayloadDataCopyWith<$Res>  {
$BridgePayloadDataCopyWith(BridgePayloadData _, $Res Function(BridgePayloadData) __);
}


/// Adds pattern-matching-related methods to [BridgePayloadData].
extension BridgePayloadDataPatterns on BridgePayloadData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePayloadData_Inline value)?  inline,TResult Function( BridgePayloadData_Deferred value)?  deferred_,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePayloadData_Inline() when inline != null:
return inline(_that);case BridgePayloadData_Deferred() when deferred_ != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePayloadData_Inline value)  inline,required TResult Function( BridgePayloadData_Deferred value)  deferred_,}){
final _that = this;
switch (_that) {
case BridgePayloadData_Inline():
return inline(_that);case BridgePayloadData_Deferred():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePayloadData_Inline value)?  inline,TResult? Function( BridgePayloadData_Deferred value)?  deferred_,}){
final _that = this;
switch (_that) {
case BridgePayloadData_Inline() when inline != null:
return inline(_that);case BridgePayloadData_Deferred() when deferred_ != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Uint8List bytes)?  inline,TResult Function( BridgeContentRef reference,  BigInt byteLength)?  deferred_,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePayloadData_Inline() when inline != null:
return inline(_that.bytes);case BridgePayloadData_Deferred() when deferred_ != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Uint8List bytes)  inline,required TResult Function( BridgeContentRef reference,  BigInt byteLength)  deferred_,}) {final _that = this;
switch (_that) {
case BridgePayloadData_Inline():
return inline(_that.bytes);case BridgePayloadData_Deferred():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Uint8List bytes)?  inline,TResult? Function( BridgeContentRef reference,  BigInt byteLength)?  deferred_,}) {final _that = this;
switch (_that) {
case BridgePayloadData_Inline() when inline != null:
return inline(_that.bytes);case BridgePayloadData_Deferred() when deferred_ != null:
return deferred_(_that.reference,_that.byteLength);case _:
  return null;

}
}

}

/// @nodoc


class BridgePayloadData_Inline extends BridgePayloadData {
  const BridgePayloadData_Inline({required this.bytes}): super._();


 final  Uint8List bytes;

/// Create a copy of BridgePayloadData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePayloadData_InlineCopyWith<BridgePayloadData_Inline> get copyWith => _$BridgePayloadData_InlineCopyWithImpl<BridgePayloadData_Inline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePayloadData_Inline&&const DeepCollectionEquality().equals(other.bytes, bytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(bytes));
}

@override
String toString() {
    return 'BridgePayloadData.inline(bytes: $bytes)';
}


}

/// @nodoc
abstract mixin class $BridgePayloadData_InlineCopyWith<$Res> implements $BridgePayloadDataCopyWith<$Res> {
  factory $BridgePayloadData_InlineCopyWith(BridgePayloadData_Inline value, $Res Function(BridgePayloadData_Inline) _then) = _$BridgePayloadData_InlineCopyWithImpl;
@useResult
$Res call({
 Uint8List bytes
});




}
/// @nodoc
class _$BridgePayloadData_InlineCopyWithImpl<$Res>
    implements $BridgePayloadData_InlineCopyWith<$Res> {
  _$BridgePayloadData_InlineCopyWithImpl(this._self, this._then);

  final BridgePayloadData_Inline _self;
  final $Res Function(BridgePayloadData_Inline) _then;

/// Create a copy of BridgePayloadData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,}) {
  return _then(BridgePayloadData_Inline(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class BridgePayloadData_Deferred extends BridgePayloadData {
  const BridgePayloadData_Deferred({required this.reference, required this.byteLength}): super._();


 final  BridgeContentRef reference;
 final  BigInt byteLength;

/// Create a copy of BridgePayloadData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePayloadData_DeferredCopyWith<BridgePayloadData_Deferred> get copyWith => _$BridgePayloadData_DeferredCopyWithImpl<BridgePayloadData_Deferred>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePayloadData_Deferred&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.byteLength, byteLength) || other.byteLength == byteLength));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,byteLength);
}

@override
String toString() {
    return 'BridgePayloadData.deferred_(reference: $reference, byteLength: $byteLength)';
}


}

/// @nodoc
abstract mixin class $BridgePayloadData_DeferredCopyWith<$Res> implements $BridgePayloadDataCopyWith<$Res> {
  factory $BridgePayloadData_DeferredCopyWith(BridgePayloadData_Deferred value, $Res Function(BridgePayloadData_Deferred) _then) = _$BridgePayloadData_DeferredCopyWithImpl;
@useResult
$Res call({
 BridgeContentRef reference, BigInt byteLength
});




}
/// @nodoc
class _$BridgePayloadData_DeferredCopyWithImpl<$Res>
    implements $BridgePayloadData_DeferredCopyWith<$Res> {
  _$BridgePayloadData_DeferredCopyWithImpl(this._self, this._then);

  final BridgePayloadData_Deferred _self;
  final $Res Function(BridgePayloadData_Deferred) _then;

/// Create a copy of BridgePayloadData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? byteLength = null,}) {
  return _then(BridgePayloadData_Deferred(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as BridgeContentRef,byteLength: null == byteLength ? _self.byteLength : byteLength // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
