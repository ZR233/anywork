// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_audience.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeBotAuthorizationHead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAuthorizationHead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotAuthorizationHead()';
}


}

/// @nodoc
class $BridgeBotAuthorizationHeadCopyWith<$Res>  {
$BridgeBotAuthorizationHeadCopyWith(BridgeBotAuthorizationHead _, $Res Function(BridgeBotAuthorizationHead) __);
}


/// Adds pattern-matching-related methods to [BridgeBotAuthorizationHead].
extension BridgeBotAuthorizationHeadPatterns on BridgeBotAuthorizationHead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotAuthorizationHead_None value)?  none,TResult Function( BridgeBotAuthorizationHead_Present value)?  present,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotAuthorizationHead_None() when none != null:
return none(_that);case BridgeBotAuthorizationHead_Present() when present != null:
return present(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotAuthorizationHead_None value)  none,required TResult Function( BridgeBotAuthorizationHead_Present value)  present,}){
final _that = this;
switch (_that) {
case BridgeBotAuthorizationHead_None():
return none(_that);case BridgeBotAuthorizationHead_Present():
return present(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotAuthorizationHead_None value)?  none,TResult? Function( BridgeBotAuthorizationHead_Present value)?  present,}){
final _that = this;
switch (_that) {
case BridgeBotAuthorizationHead_None() when none != null:
return none(_that);case BridgeBotAuthorizationHead_Present() when present != null:
return present(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  none,TResult Function( BridgeBotAuthorizationRef authorization)?  present,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotAuthorizationHead_None() when none != null:
return none();case BridgeBotAuthorizationHead_Present() when present != null:
return present(_that.authorization);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  none,required TResult Function( BridgeBotAuthorizationRef authorization)  present,}) {final _that = this;
switch (_that) {
case BridgeBotAuthorizationHead_None():
return none();case BridgeBotAuthorizationHead_Present():
return present(_that.authorization);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  none,TResult? Function( BridgeBotAuthorizationRef authorization)?  present,}) {final _that = this;
switch (_that) {
case BridgeBotAuthorizationHead_None() when none != null:
return none();case BridgeBotAuthorizationHead_Present() when present != null:
return present(_that.authorization);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotAuthorizationHead_None extends BridgeBotAuthorizationHead {
  const BridgeBotAuthorizationHead_None(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAuthorizationHead_None);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotAuthorizationHead.none()';
}


}




/// @nodoc


class BridgeBotAuthorizationHead_Present extends BridgeBotAuthorizationHead {
  const BridgeBotAuthorizationHead_Present({required this.authorization}): super._();


 final  BridgeBotAuthorizationRef authorization;

/// Create a copy of BridgeBotAuthorizationHead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotAuthorizationHead_PresentCopyWith<BridgeBotAuthorizationHead_Present> get copyWith => _$BridgeBotAuthorizationHead_PresentCopyWithImpl<BridgeBotAuthorizationHead_Present>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotAuthorizationHead_Present&&(identical(other.authorization, authorization) || other.authorization == authorization));
}


@override
int get hashCode {
    return Object.hash(runtimeType,authorization);
}

@override
String toString() {
    return 'BridgeBotAuthorizationHead.present(authorization: $authorization)';
}


}

/// @nodoc
abstract mixin class $BridgeBotAuthorizationHead_PresentCopyWith<$Res> implements $BridgeBotAuthorizationHeadCopyWith<$Res> {
  factory $BridgeBotAuthorizationHead_PresentCopyWith(BridgeBotAuthorizationHead_Present value, $Res Function(BridgeBotAuthorizationHead_Present) _then) = _$BridgeBotAuthorizationHead_PresentCopyWithImpl;
@useResult
$Res call({
 BridgeBotAuthorizationRef authorization
});




}
/// @nodoc
class _$BridgeBotAuthorizationHead_PresentCopyWithImpl<$Res>
    implements $BridgeBotAuthorizationHead_PresentCopyWith<$Res> {
  _$BridgeBotAuthorizationHead_PresentCopyWithImpl(this._self, this._then);

  final BridgeBotAuthorizationHead_Present _self;
  final $Res Function(BridgeBotAuthorizationHead_Present) _then;

/// Create a copy of BridgeBotAuthorizationHead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? authorization = null,}) {
  return _then(BridgeBotAuthorizationHead_Present(
authorization: null == authorization ? _self.authorization : authorization // ignore: cast_nullable_to_non_nullable
as BridgeBotAuthorizationRef,
  ));
}


}

/// @nodoc
mixin _$BridgeBotClosedStart {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotClosedStart);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotClosedStart()';
}


}

/// @nodoc
class $BridgeBotClosedStartCopyWith<$Res>  {
$BridgeBotClosedStartCopyWith(BridgeBotClosedStart _, $Res Function(BridgeBotClosedStart) __);
}


/// Adds pattern-matching-related methods to [BridgeBotClosedStart].
extension BridgeBotClosedStartPatterns on BridgeBotClosedStart {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotClosedStart_NeverActivated value)?  neverActivated,TResult Function( BridgeBotClosedStart_Saved value)?  saved,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotClosedStart_NeverActivated() when neverActivated != null:
return neverActivated(_that);case BridgeBotClosedStart_Saved() when saved != null:
return saved(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotClosedStart_NeverActivated value)  neverActivated,required TResult Function( BridgeBotClosedStart_Saved value)  saved,}){
final _that = this;
switch (_that) {
case BridgeBotClosedStart_NeverActivated():
return neverActivated(_that);case BridgeBotClosedStart_Saved():
return saved(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotClosedStart_NeverActivated value)?  neverActivated,TResult? Function( BridgeBotClosedStart_Saved value)?  saved,}){
final _that = this;
switch (_that) {
case BridgeBotClosedStart_NeverActivated() when neverActivated != null:
return neverActivated(_that);case BridgeBotClosedStart_Saved() when saved != null:
return saved(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  neverActivated,TResult Function( BridgeBotAudienceStart start)?  saved,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotClosedStart_NeverActivated() when neverActivated != null:
return neverActivated();case BridgeBotClosedStart_Saved() when saved != null:
return saved(_that.start);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  neverActivated,required TResult Function( BridgeBotAudienceStart start)  saved,}) {final _that = this;
switch (_that) {
case BridgeBotClosedStart_NeverActivated():
return neverActivated();case BridgeBotClosedStart_Saved():
return saved(_that.start);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  neverActivated,TResult? Function( BridgeBotAudienceStart start)?  saved,}) {final _that = this;
switch (_that) {
case BridgeBotClosedStart_NeverActivated() when neverActivated != null:
return neverActivated();case BridgeBotClosedStart_Saved() when saved != null:
return saved(_that.start);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotClosedStart_NeverActivated extends BridgeBotClosedStart {
  const BridgeBotClosedStart_NeverActivated(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotClosedStart_NeverActivated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotClosedStart.neverActivated()';
}


}




/// @nodoc


class BridgeBotClosedStart_Saved extends BridgeBotClosedStart {
  const BridgeBotClosedStart_Saved({required this.start}): super._();


 final  BridgeBotAudienceStart start;

/// Create a copy of BridgeBotClosedStart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotClosedStart_SavedCopyWith<BridgeBotClosedStart_Saved> get copyWith => _$BridgeBotClosedStart_SavedCopyWithImpl<BridgeBotClosedStart_Saved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotClosedStart_Saved&&(identical(other.start, start) || other.start == start));
}


@override
int get hashCode {
    return Object.hash(runtimeType,start);
}

@override
String toString() {
    return 'BridgeBotClosedStart.saved(start: $start)';
}


}

/// @nodoc
abstract mixin class $BridgeBotClosedStart_SavedCopyWith<$Res> implements $BridgeBotClosedStartCopyWith<$Res> {
  factory $BridgeBotClosedStart_SavedCopyWith(BridgeBotClosedStart_Saved value, $Res Function(BridgeBotClosedStart_Saved) _then) = _$BridgeBotClosedStart_SavedCopyWithImpl;
@useResult
$Res call({
 BridgeBotAudienceStart start
});




}
/// @nodoc
class _$BridgeBotClosedStart_SavedCopyWithImpl<$Res>
    implements $BridgeBotClosedStart_SavedCopyWith<$Res> {
  _$BridgeBotClosedStart_SavedCopyWithImpl(this._self, this._then);

  final BridgeBotClosedStart_Saved _self;
  final $Res Function(BridgeBotClosedStart_Saved) _then;

/// Create a copy of BridgeBotClosedStart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? start = null,}) {
  return _then(BridgeBotClosedStart_Saved(
start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as BridgeBotAudienceStart,
  ));
}


}

/// @nodoc
mixin _$BridgeBotCurrentSync {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCurrentSync);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotCurrentSync()';
}


}

/// @nodoc
class $BridgeBotCurrentSyncCopyWith<$Res>  {
$BridgeBotCurrentSyncCopyWith(BridgeBotCurrentSync _, $Res Function(BridgeBotCurrentSync) __);
}


/// Adds pattern-matching-related methods to [BridgeBotCurrentSync].
extension BridgeBotCurrentSyncPatterns on BridgeBotCurrentSync {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotCurrentSync_PreparingThread value)?  preparingThread,TResult Function( BridgeBotCurrentSync_RequiresUpgrade value)?  requiresUpgrade,TResult Function( BridgeBotCurrentSync_PendingStart value)?  pendingStart,TResult Function( BridgeBotCurrentSync_Active value)?  active,TResult Function( BridgeBotCurrentSync_Paused value)?  paused,TResult Function( BridgeBotCurrentSync_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotCurrentSync_PreparingThread() when preparingThread != null:
return preparingThread(_that);case BridgeBotCurrentSync_RequiresUpgrade() when requiresUpgrade != null:
return requiresUpgrade(_that);case BridgeBotCurrentSync_PendingStart() when pendingStart != null:
return pendingStart(_that);case BridgeBotCurrentSync_Active() when active != null:
return active(_that);case BridgeBotCurrentSync_Paused() when paused != null:
return paused(_that);case BridgeBotCurrentSync_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotCurrentSync_PreparingThread value)  preparingThread,required TResult Function( BridgeBotCurrentSync_RequiresUpgrade value)  requiresUpgrade,required TResult Function( BridgeBotCurrentSync_PendingStart value)  pendingStart,required TResult Function( BridgeBotCurrentSync_Active value)  active,required TResult Function( BridgeBotCurrentSync_Paused value)  paused,required TResult Function( BridgeBotCurrentSync_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeBotCurrentSync_PreparingThread():
return preparingThread(_that);case BridgeBotCurrentSync_RequiresUpgrade():
return requiresUpgrade(_that);case BridgeBotCurrentSync_PendingStart():
return pendingStart(_that);case BridgeBotCurrentSync_Active():
return active(_that);case BridgeBotCurrentSync_Paused():
return paused(_that);case BridgeBotCurrentSync_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotCurrentSync_PreparingThread value)?  preparingThread,TResult? Function( BridgeBotCurrentSync_RequiresUpgrade value)?  requiresUpgrade,TResult? Function( BridgeBotCurrentSync_PendingStart value)?  pendingStart,TResult? Function( BridgeBotCurrentSync_Active value)?  active,TResult? Function( BridgeBotCurrentSync_Paused value)?  paused,TResult? Function( BridgeBotCurrentSync_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeBotCurrentSync_PreparingThread() when preparingThread != null:
return preparingThread(_that);case BridgeBotCurrentSync_RequiresUpgrade() when requiresUpgrade != null:
return requiresUpgrade(_that);case BridgeBotCurrentSync_PendingStart() when pendingStart != null:
return pendingStart(_that);case BridgeBotCurrentSync_Active() when active != null:
return active(_that);case BridgeBotCurrentSync_Paused() when paused != null:
return paused(_that);case BridgeBotCurrentSync_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  preparingThread,TResult Function()?  requiresUpgrade,TResult Function( BridgeBotPendingAuthorization pending)?  pendingStart,TResult Function( BridgeBotStartedAuthorization authorization)?  active,TResult Function( BridgeBotStartedAuthorization authorization)?  paused,TResult Function()?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotCurrentSync_PreparingThread() when preparingThread != null:
return preparingThread();case BridgeBotCurrentSync_RequiresUpgrade() when requiresUpgrade != null:
return requiresUpgrade();case BridgeBotCurrentSync_PendingStart() when pendingStart != null:
return pendingStart(_that.pending);case BridgeBotCurrentSync_Active() when active != null:
return active(_that.authorization);case BridgeBotCurrentSync_Paused() when paused != null:
return paused(_that.authorization);case BridgeBotCurrentSync_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  preparingThread,required TResult Function()  requiresUpgrade,required TResult Function( BridgeBotPendingAuthorization pending)  pendingStart,required TResult Function( BridgeBotStartedAuthorization authorization)  active,required TResult Function( BridgeBotStartedAuthorization authorization)  paused,required TResult Function()  closed,}) {final _that = this;
switch (_that) {
case BridgeBotCurrentSync_PreparingThread():
return preparingThread();case BridgeBotCurrentSync_RequiresUpgrade():
return requiresUpgrade();case BridgeBotCurrentSync_PendingStart():
return pendingStart(_that.pending);case BridgeBotCurrentSync_Active():
return active(_that.authorization);case BridgeBotCurrentSync_Paused():
return paused(_that.authorization);case BridgeBotCurrentSync_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  preparingThread,TResult? Function()?  requiresUpgrade,TResult? Function( BridgeBotPendingAuthorization pending)?  pendingStart,TResult? Function( BridgeBotStartedAuthorization authorization)?  active,TResult? Function( BridgeBotStartedAuthorization authorization)?  paused,TResult? Function()?  closed,}) {final _that = this;
switch (_that) {
case BridgeBotCurrentSync_PreparingThread() when preparingThread != null:
return preparingThread();case BridgeBotCurrentSync_RequiresUpgrade() when requiresUpgrade != null:
return requiresUpgrade();case BridgeBotCurrentSync_PendingStart() when pendingStart != null:
return pendingStart(_that.pending);case BridgeBotCurrentSync_Active() when active != null:
return active(_that.authorization);case BridgeBotCurrentSync_Paused() when paused != null:
return paused(_that.authorization);case BridgeBotCurrentSync_Closed() when closed != null:
return closed();case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotCurrentSync_PreparingThread extends BridgeBotCurrentSync {
  const BridgeBotCurrentSync_PreparingThread(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCurrentSync_PreparingThread);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotCurrentSync.preparingThread()';
}


}




/// @nodoc


class BridgeBotCurrentSync_RequiresUpgrade extends BridgeBotCurrentSync {
  const BridgeBotCurrentSync_RequiresUpgrade(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCurrentSync_RequiresUpgrade);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotCurrentSync.requiresUpgrade()';
}


}




/// @nodoc


class BridgeBotCurrentSync_PendingStart extends BridgeBotCurrentSync {
  const BridgeBotCurrentSync_PendingStart({required this.pending}): super._();


 final  BridgeBotPendingAuthorization pending;

/// Create a copy of BridgeBotCurrentSync
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotCurrentSync_PendingStartCopyWith<BridgeBotCurrentSync_PendingStart> get copyWith => _$BridgeBotCurrentSync_PendingStartCopyWithImpl<BridgeBotCurrentSync_PendingStart>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCurrentSync_PendingStart&&(identical(other.pending, pending) || other.pending == pending));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pending);
}

@override
String toString() {
    return 'BridgeBotCurrentSync.pendingStart(pending: $pending)';
}


}

/// @nodoc
abstract mixin class $BridgeBotCurrentSync_PendingStartCopyWith<$Res> implements $BridgeBotCurrentSyncCopyWith<$Res> {
  factory $BridgeBotCurrentSync_PendingStartCopyWith(BridgeBotCurrentSync_PendingStart value, $Res Function(BridgeBotCurrentSync_PendingStart) _then) = _$BridgeBotCurrentSync_PendingStartCopyWithImpl;
@useResult
$Res call({
 BridgeBotPendingAuthorization pending
});




}
/// @nodoc
class _$BridgeBotCurrentSync_PendingStartCopyWithImpl<$Res>
    implements $BridgeBotCurrentSync_PendingStartCopyWith<$Res> {
  _$BridgeBotCurrentSync_PendingStartCopyWithImpl(this._self, this._then);

  final BridgeBotCurrentSync_PendingStart _self;
  final $Res Function(BridgeBotCurrentSync_PendingStart) _then;

/// Create a copy of BridgeBotCurrentSync
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pending = null,}) {
  return _then(BridgeBotCurrentSync_PendingStart(
pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as BridgeBotPendingAuthorization,
  ));
}


}

/// @nodoc


class BridgeBotCurrentSync_Active extends BridgeBotCurrentSync {
  const BridgeBotCurrentSync_Active({required this.authorization}): super._();


 final  BridgeBotStartedAuthorization authorization;

/// Create a copy of BridgeBotCurrentSync
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotCurrentSync_ActiveCopyWith<BridgeBotCurrentSync_Active> get copyWith => _$BridgeBotCurrentSync_ActiveCopyWithImpl<BridgeBotCurrentSync_Active>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCurrentSync_Active&&(identical(other.authorization, authorization) || other.authorization == authorization));
}


@override
int get hashCode {
    return Object.hash(runtimeType,authorization);
}

@override
String toString() {
    return 'BridgeBotCurrentSync.active(authorization: $authorization)';
}


}

/// @nodoc
abstract mixin class $BridgeBotCurrentSync_ActiveCopyWith<$Res> implements $BridgeBotCurrentSyncCopyWith<$Res> {
  factory $BridgeBotCurrentSync_ActiveCopyWith(BridgeBotCurrentSync_Active value, $Res Function(BridgeBotCurrentSync_Active) _then) = _$BridgeBotCurrentSync_ActiveCopyWithImpl;
@useResult
$Res call({
 BridgeBotStartedAuthorization authorization
});




}
/// @nodoc
class _$BridgeBotCurrentSync_ActiveCopyWithImpl<$Res>
    implements $BridgeBotCurrentSync_ActiveCopyWith<$Res> {
  _$BridgeBotCurrentSync_ActiveCopyWithImpl(this._self, this._then);

  final BridgeBotCurrentSync_Active _self;
  final $Res Function(BridgeBotCurrentSync_Active) _then;

/// Create a copy of BridgeBotCurrentSync
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? authorization = null,}) {
  return _then(BridgeBotCurrentSync_Active(
authorization: null == authorization ? _self.authorization : authorization // ignore: cast_nullable_to_non_nullable
as BridgeBotStartedAuthorization,
  ));
}


}

/// @nodoc


class BridgeBotCurrentSync_Paused extends BridgeBotCurrentSync {
  const BridgeBotCurrentSync_Paused({required this.authorization}): super._();


 final  BridgeBotStartedAuthorization authorization;

/// Create a copy of BridgeBotCurrentSync
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotCurrentSync_PausedCopyWith<BridgeBotCurrentSync_Paused> get copyWith => _$BridgeBotCurrentSync_PausedCopyWithImpl<BridgeBotCurrentSync_Paused>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCurrentSync_Paused&&(identical(other.authorization, authorization) || other.authorization == authorization));
}


@override
int get hashCode {
    return Object.hash(runtimeType,authorization);
}

@override
String toString() {
    return 'BridgeBotCurrentSync.paused(authorization: $authorization)';
}


}

/// @nodoc
abstract mixin class $BridgeBotCurrentSync_PausedCopyWith<$Res> implements $BridgeBotCurrentSyncCopyWith<$Res> {
  factory $BridgeBotCurrentSync_PausedCopyWith(BridgeBotCurrentSync_Paused value, $Res Function(BridgeBotCurrentSync_Paused) _then) = _$BridgeBotCurrentSync_PausedCopyWithImpl;
@useResult
$Res call({
 BridgeBotStartedAuthorization authorization
});




}
/// @nodoc
class _$BridgeBotCurrentSync_PausedCopyWithImpl<$Res>
    implements $BridgeBotCurrentSync_PausedCopyWith<$Res> {
  _$BridgeBotCurrentSync_PausedCopyWithImpl(this._self, this._then);

  final BridgeBotCurrentSync_Paused _self;
  final $Res Function(BridgeBotCurrentSync_Paused) _then;

/// Create a copy of BridgeBotCurrentSync
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? authorization = null,}) {
  return _then(BridgeBotCurrentSync_Paused(
authorization: null == authorization ? _self.authorization : authorization // ignore: cast_nullable_to_non_nullable
as BridgeBotStartedAuthorization,
  ));
}


}

/// @nodoc


class BridgeBotCurrentSync_Closed extends BridgeBotCurrentSync {
  const BridgeBotCurrentSync_Closed(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCurrentSync_Closed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotCurrentSync.closed()';
}


}




/// @nodoc
mixin _$BridgeBotThreadBindingPosition {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotThreadBindingPosition);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotThreadBindingPosition()';
}


}

/// @nodoc
class $BridgeBotThreadBindingPositionCopyWith<$Res>  {
$BridgeBotThreadBindingPositionCopyWith(BridgeBotThreadBindingPosition _, $Res Function(BridgeBotThreadBindingPosition) __);
}


/// Adds pattern-matching-related methods to [BridgeBotThreadBindingPosition].
extension BridgeBotThreadBindingPositionPatterns on BridgeBotThreadBindingPosition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotThreadBindingPosition_Current value)?  current,TResult Function( BridgeBotThreadBindingPosition_Replaced value)?  replaced,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotThreadBindingPosition_Current() when current != null:
return current(_that);case BridgeBotThreadBindingPosition_Replaced() when replaced != null:
return replaced(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotThreadBindingPosition_Current value)  current,required TResult Function( BridgeBotThreadBindingPosition_Replaced value)  replaced,}){
final _that = this;
switch (_that) {
case BridgeBotThreadBindingPosition_Current():
return current(_that);case BridgeBotThreadBindingPosition_Replaced():
return replaced(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotThreadBindingPosition_Current value)?  current,TResult? Function( BridgeBotThreadBindingPosition_Replaced value)?  replaced,}){
final _that = this;
switch (_that) {
case BridgeBotThreadBindingPosition_Current() when current != null:
return current(_that);case BridgeBotThreadBindingPosition_Replaced() when replaced != null:
return replaced(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeBotSyncCas cas,  BridgeBotCurrentSync sync_)?  current,TResult Function( BigInt lastBindingRevision,  BigInt currentBindingRevision)?  replaced,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotThreadBindingPosition_Current() when current != null:
return current(_that.cas,_that.sync_);case BridgeBotThreadBindingPosition_Replaced() when replaced != null:
return replaced(_that.lastBindingRevision,_that.currentBindingRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeBotSyncCas cas,  BridgeBotCurrentSync sync_)  current,required TResult Function( BigInt lastBindingRevision,  BigInt currentBindingRevision)  replaced,}) {final _that = this;
switch (_that) {
case BridgeBotThreadBindingPosition_Current():
return current(_that.cas,_that.sync_);case BridgeBotThreadBindingPosition_Replaced():
return replaced(_that.lastBindingRevision,_that.currentBindingRevision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeBotSyncCas cas,  BridgeBotCurrentSync sync_)?  current,TResult? Function( BigInt lastBindingRevision,  BigInt currentBindingRevision)?  replaced,}) {final _that = this;
switch (_that) {
case BridgeBotThreadBindingPosition_Current() when current != null:
return current(_that.cas,_that.sync_);case BridgeBotThreadBindingPosition_Replaced() when replaced != null:
return replaced(_that.lastBindingRevision,_that.currentBindingRevision);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotThreadBindingPosition_Current extends BridgeBotThreadBindingPosition {
  const BridgeBotThreadBindingPosition_Current({required this.cas, required this.sync_}): super._();


 final  BridgeBotSyncCas cas;
 final  BridgeBotCurrentSync sync_;

/// Create a copy of BridgeBotThreadBindingPosition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotThreadBindingPosition_CurrentCopyWith<BridgeBotThreadBindingPosition_Current> get copyWith => _$BridgeBotThreadBindingPosition_CurrentCopyWithImpl<BridgeBotThreadBindingPosition_Current>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotThreadBindingPosition_Current&&(identical(other.cas, cas) || other.cas == cas)&&(identical(other.sync_, sync_) || other.sync_ == sync_));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cas,sync_);
}

@override
String toString() {
    return 'BridgeBotThreadBindingPosition.current(cas: $cas, sync_: $sync_)';
}


}

/// @nodoc
abstract mixin class $BridgeBotThreadBindingPosition_CurrentCopyWith<$Res> implements $BridgeBotThreadBindingPositionCopyWith<$Res> {
  factory $BridgeBotThreadBindingPosition_CurrentCopyWith(BridgeBotThreadBindingPosition_Current value, $Res Function(BridgeBotThreadBindingPosition_Current) _then) = _$BridgeBotThreadBindingPosition_CurrentCopyWithImpl;
@useResult
$Res call({
 BridgeBotSyncCas cas, BridgeBotCurrentSync sync_
});


$BridgeBotCurrentSyncCopyWith<$Res> get sync_;

}
/// @nodoc
class _$BridgeBotThreadBindingPosition_CurrentCopyWithImpl<$Res>
    implements $BridgeBotThreadBindingPosition_CurrentCopyWith<$Res> {
  _$BridgeBotThreadBindingPosition_CurrentCopyWithImpl(this._self, this._then);

  final BridgeBotThreadBindingPosition_Current _self;
  final $Res Function(BridgeBotThreadBindingPosition_Current) _then;

/// Create a copy of BridgeBotThreadBindingPosition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cas = null,Object? sync_ = null,}) {
  return _then(BridgeBotThreadBindingPosition_Current(
cas: null == cas ? _self.cas : cas // ignore: cast_nullable_to_non_nullable
as BridgeBotSyncCas,sync_: null == sync_ ? _self.sync_ : sync_ // ignore: cast_nullable_to_non_nullable
as BridgeBotCurrentSync,
  ));
}

/// Create a copy of BridgeBotThreadBindingPosition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeBotCurrentSyncCopyWith<$Res> get sync_ {

  return $BridgeBotCurrentSyncCopyWith<$Res>(_self.sync_, (value) {
    return _then(_self.copyWith(sync_: value));
  });
}
}

/// @nodoc


class BridgeBotThreadBindingPosition_Replaced extends BridgeBotThreadBindingPosition {
  const BridgeBotThreadBindingPosition_Replaced({required this.lastBindingRevision, required this.currentBindingRevision}): super._();


 final  BigInt lastBindingRevision;
 final  BigInt currentBindingRevision;

/// Create a copy of BridgeBotThreadBindingPosition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotThreadBindingPosition_ReplacedCopyWith<BridgeBotThreadBindingPosition_Replaced> get copyWith => _$BridgeBotThreadBindingPosition_ReplacedCopyWithImpl<BridgeBotThreadBindingPosition_Replaced>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotThreadBindingPosition_Replaced&&(identical(other.lastBindingRevision, lastBindingRevision) || other.lastBindingRevision == lastBindingRevision)&&(identical(other.currentBindingRevision, currentBindingRevision) || other.currentBindingRevision == currentBindingRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,lastBindingRevision,currentBindingRevision);
}

@override
String toString() {
    return 'BridgeBotThreadBindingPosition.replaced(lastBindingRevision: $lastBindingRevision, currentBindingRevision: $currentBindingRevision)';
}


}

/// @nodoc
abstract mixin class $BridgeBotThreadBindingPosition_ReplacedCopyWith<$Res> implements $BridgeBotThreadBindingPositionCopyWith<$Res> {
  factory $BridgeBotThreadBindingPosition_ReplacedCopyWith(BridgeBotThreadBindingPosition_Replaced value, $Res Function(BridgeBotThreadBindingPosition_Replaced) _then) = _$BridgeBotThreadBindingPosition_ReplacedCopyWithImpl;
@useResult
$Res call({
 BigInt lastBindingRevision, BigInt currentBindingRevision
});




}
/// @nodoc
class _$BridgeBotThreadBindingPosition_ReplacedCopyWithImpl<$Res>
    implements $BridgeBotThreadBindingPosition_ReplacedCopyWith<$Res> {
  _$BridgeBotThreadBindingPosition_ReplacedCopyWithImpl(this._self, this._then);

  final BridgeBotThreadBindingPosition_Replaced _self;
  final $Res Function(BridgeBotThreadBindingPosition_Replaced) _then;

/// Create a copy of BridgeBotThreadBindingPosition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? lastBindingRevision = null,Object? currentBindingRevision = null,}) {
  return _then(BridgeBotThreadBindingPosition_Replaced(
lastBindingRevision: null == lastBindingRevision ? _self.lastBindingRevision : lastBindingRevision // ignore: cast_nullable_to_non_nullable
as BigInt,currentBindingRevision: null == currentBindingRevision ? _self.currentBindingRevision : currentBindingRevision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadAudience {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAudience);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadAudience()';
}


}

/// @nodoc
class $BridgeThreadAudienceCopyWith<$Res>  {
$BridgeThreadAudienceCopyWith(BridgeThreadAudience _, $Res Function(BridgeThreadAudience) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadAudience].
extension BridgeThreadAudiencePatterns on BridgeThreadAudience {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadAudience_Unbound value)?  unbound,TResult Function( BridgeThreadAudience_Unavailable value)?  unavailable,TResult Function( BridgeThreadAudience_Known value)?  known,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadAudience_Unbound() when unbound != null:
return unbound(_that);case BridgeThreadAudience_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeThreadAudience_Known() when known != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadAudience_Unbound value)  unbound,required TResult Function( BridgeThreadAudience_Unavailable value)  unavailable,required TResult Function( BridgeThreadAudience_Known value)  known,}){
final _that = this;
switch (_that) {
case BridgeThreadAudience_Unbound():
return unbound(_that);case BridgeThreadAudience_Unavailable():
return unavailable(_that);case BridgeThreadAudience_Known():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadAudience_Unbound value)?  unbound,TResult? Function( BridgeThreadAudience_Unavailable value)?  unavailable,TResult? Function( BridgeThreadAudience_Known value)?  known,}){
final _that = this;
switch (_that) {
case BridgeThreadAudience_Unbound() when unbound != null:
return unbound(_that);case BridgeThreadAudience_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeThreadAudience_Known() when known != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unbound,TResult Function( BridgeThreadAudienceUnavailableReason reason)?  unavailable,TResult Function( BridgeBotThreadAudience audience)?  known,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadAudience_Unbound() when unbound != null:
return unbound();case BridgeThreadAudience_Unavailable() when unavailable != null:
return unavailable(_that.reason);case BridgeThreadAudience_Known() when known != null:
return known(_that.audience);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unbound,required TResult Function( BridgeThreadAudienceUnavailableReason reason)  unavailable,required TResult Function( BridgeBotThreadAudience audience)  known,}) {final _that = this;
switch (_that) {
case BridgeThreadAudience_Unbound():
return unbound();case BridgeThreadAudience_Unavailable():
return unavailable(_that.reason);case BridgeThreadAudience_Known():
return known(_that.audience);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unbound,TResult? Function( BridgeThreadAudienceUnavailableReason reason)?  unavailable,TResult? Function( BridgeBotThreadAudience audience)?  known,}) {final _that = this;
switch (_that) {
case BridgeThreadAudience_Unbound() when unbound != null:
return unbound();case BridgeThreadAudience_Unavailable() when unavailable != null:
return unavailable(_that.reason);case BridgeThreadAudience_Known() when known != null:
return known(_that.audience);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadAudience_Unbound extends BridgeThreadAudience {
  const BridgeThreadAudience_Unbound(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAudience_Unbound);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadAudience.unbound()';
}


}




/// @nodoc


class BridgeThreadAudience_Unavailable extends BridgeThreadAudience {
  const BridgeThreadAudience_Unavailable({required this.reason}): super._();


 final  BridgeThreadAudienceUnavailableReason reason;

/// Create a copy of BridgeThreadAudience
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadAudience_UnavailableCopyWith<BridgeThreadAudience_Unavailable> get copyWith => _$BridgeThreadAudience_UnavailableCopyWithImpl<BridgeThreadAudience_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAudience_Unavailable&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'BridgeThreadAudience.unavailable(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadAudience_UnavailableCopyWith<$Res> implements $BridgeThreadAudienceCopyWith<$Res> {
  factory $BridgeThreadAudience_UnavailableCopyWith(BridgeThreadAudience_Unavailable value, $Res Function(BridgeThreadAudience_Unavailable) _then) = _$BridgeThreadAudience_UnavailableCopyWithImpl;
@useResult
$Res call({
 BridgeThreadAudienceUnavailableReason reason
});




}
/// @nodoc
class _$BridgeThreadAudience_UnavailableCopyWithImpl<$Res>
    implements $BridgeThreadAudience_UnavailableCopyWith<$Res> {
  _$BridgeThreadAudience_UnavailableCopyWithImpl(this._self, this._then);

  final BridgeThreadAudience_Unavailable _self;
  final $Res Function(BridgeThreadAudience_Unavailable) _then;

/// Create a copy of BridgeThreadAudience
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeThreadAudience_Unavailable(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeThreadAudienceUnavailableReason,
  ));
}


}

/// @nodoc


class BridgeThreadAudience_Known extends BridgeThreadAudience {
  const BridgeThreadAudience_Known({required this.audience}): super._();


 final  BridgeBotThreadAudience audience;

/// Create a copy of BridgeThreadAudience
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadAudience_KnownCopyWith<BridgeThreadAudience_Known> get copyWith => _$BridgeThreadAudience_KnownCopyWithImpl<BridgeThreadAudience_Known>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAudience_Known&&(identical(other.audience, audience) || other.audience == audience));
}


@override
int get hashCode {
    return Object.hash(runtimeType,audience);
}

@override
String toString() {
    return 'BridgeThreadAudience.known(audience: $audience)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadAudience_KnownCopyWith<$Res> implements $BridgeThreadAudienceCopyWith<$Res> {
  factory $BridgeThreadAudience_KnownCopyWith(BridgeThreadAudience_Known value, $Res Function(BridgeThreadAudience_Known) _then) = _$BridgeThreadAudience_KnownCopyWithImpl;
@useResult
$Res call({
 BridgeBotThreadAudience audience
});




}
/// @nodoc
class _$BridgeThreadAudience_KnownCopyWithImpl<$Res>
    implements $BridgeThreadAudience_KnownCopyWith<$Res> {
  _$BridgeThreadAudience_KnownCopyWithImpl(this._self, this._then);

  final BridgeThreadAudience_Known _self;
  final $Res Function(BridgeThreadAudience_Known) _then;

/// Create a copy of BridgeThreadAudience
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? audience = null,}) {
  return _then(BridgeThreadAudience_Known(
audience: null == audience ? _self.audience : audience // ignore: cast_nullable_to_non_nullable
as BridgeBotThreadAudience,
  ));
}


}

// dart format on
