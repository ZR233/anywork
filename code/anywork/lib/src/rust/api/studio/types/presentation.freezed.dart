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
mixin _$BridgeDisplayBlockBody {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayBlockBody);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeDisplayBlockBody()';
}


}

/// @nodoc
class $BridgeDisplayBlockBodyCopyWith<$Res>  {
$BridgeDisplayBlockBodyCopyWith(BridgeDisplayBlockBody _, $Res Function(BridgeDisplayBlockBody) __);
}


/// Adds pattern-matching-related methods to [BridgeDisplayBlockBody].
extension BridgeDisplayBlockBodyPatterns on BridgeDisplayBlockBody {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeDisplayBlockBody_Work value)?  work,TResult Function( BridgeDisplayBlockBody_Single value)?  single,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeDisplayBlockBody_Work() when work != null:
return work(_that);case BridgeDisplayBlockBody_Single() when single != null:
return single(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeDisplayBlockBody_Work value)  work,required TResult Function( BridgeDisplayBlockBody_Single value)  single,}){
final _that = this;
switch (_that) {
case BridgeDisplayBlockBody_Work():
return work(_that);case BridgeDisplayBlockBody_Single():
return single(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeDisplayBlockBody_Work value)?  work,TResult? Function( BridgeDisplayBlockBody_Single value)?  single,}){
final _that = this;
switch (_that) {
case BridgeDisplayBlockBody_Work() when work != null:
return work(_that);case BridgeDisplayBlockBody_Single() when single != null:
return single(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeWorkTiming timing,  BridgeDisplayBlockRef members)?  work,TResult Function( BridgeDisplayRecord record,  BridgeSingleVisibility visibility)?  single,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeDisplayBlockBody_Work() when work != null:
return work(_that.timing,_that.members);case BridgeDisplayBlockBody_Single() when single != null:
return single(_that.record,_that.visibility);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeWorkTiming timing,  BridgeDisplayBlockRef members)  work,required TResult Function( BridgeDisplayRecord record,  BridgeSingleVisibility visibility)  single,}) {final _that = this;
switch (_that) {
case BridgeDisplayBlockBody_Work():
return work(_that.timing,_that.members);case BridgeDisplayBlockBody_Single():
return single(_that.record,_that.visibility);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeWorkTiming timing,  BridgeDisplayBlockRef members)?  work,TResult? Function( BridgeDisplayRecord record,  BridgeSingleVisibility visibility)?  single,}) {final _that = this;
switch (_that) {
case BridgeDisplayBlockBody_Work() when work != null:
return work(_that.timing,_that.members);case BridgeDisplayBlockBody_Single() when single != null:
return single(_that.record,_that.visibility);case _:
  return null;

}
}

}

/// @nodoc


class BridgeDisplayBlockBody_Work extends BridgeDisplayBlockBody {
  const BridgeDisplayBlockBody_Work({required this.timing, required this.members}): super._();


 final  BridgeWorkTiming timing;
 final  BridgeDisplayBlockRef members;

/// Create a copy of BridgeDisplayBlockBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDisplayBlockBody_WorkCopyWith<BridgeDisplayBlockBody_Work> get copyWith => _$BridgeDisplayBlockBody_WorkCopyWithImpl<BridgeDisplayBlockBody_Work>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayBlockBody_Work&&(identical(other.timing, timing) || other.timing == timing)&&(identical(other.members, members) || other.members == members));
}


@override
int get hashCode {
    return Object.hash(runtimeType,timing,members);
}

@override
String toString() {
    return 'BridgeDisplayBlockBody.work(timing: $timing, members: $members)';
}


}

/// @nodoc
abstract mixin class $BridgeDisplayBlockBody_WorkCopyWith<$Res> implements $BridgeDisplayBlockBodyCopyWith<$Res> {
  factory $BridgeDisplayBlockBody_WorkCopyWith(BridgeDisplayBlockBody_Work value, $Res Function(BridgeDisplayBlockBody_Work) _then) = _$BridgeDisplayBlockBody_WorkCopyWithImpl;
@useResult
$Res call({
 BridgeWorkTiming timing, BridgeDisplayBlockRef members
});




}
/// @nodoc
class _$BridgeDisplayBlockBody_WorkCopyWithImpl<$Res>
    implements $BridgeDisplayBlockBody_WorkCopyWith<$Res> {
  _$BridgeDisplayBlockBody_WorkCopyWithImpl(this._self, this._then);

  final BridgeDisplayBlockBody_Work _self;
  final $Res Function(BridgeDisplayBlockBody_Work) _then;

/// Create a copy of BridgeDisplayBlockBody
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? timing = null,Object? members = null,}) {
  return _then(BridgeDisplayBlockBody_Work(
timing: null == timing ? _self.timing : timing // ignore: cast_nullable_to_non_nullable
as BridgeWorkTiming,members: null == members ? _self.members : members // ignore: cast_nullable_to_non_nullable
as BridgeDisplayBlockRef,
  ));
}


}

/// @nodoc


class BridgeDisplayBlockBody_Single extends BridgeDisplayBlockBody {
  const BridgeDisplayBlockBody_Single({required this.record, required this.visibility}): super._();


 final  BridgeDisplayRecord record;
 final  BridgeSingleVisibility visibility;

/// Create a copy of BridgeDisplayBlockBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDisplayBlockBody_SingleCopyWith<BridgeDisplayBlockBody_Single> get copyWith => _$BridgeDisplayBlockBody_SingleCopyWithImpl<BridgeDisplayBlockBody_Single>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayBlockBody_Single&&(identical(other.record, record) || other.record == record)&&(identical(other.visibility, visibility) || other.visibility == visibility));
}


@override
int get hashCode {
    return Object.hash(runtimeType,record,visibility);
}

@override
String toString() {
    return 'BridgeDisplayBlockBody.single(record: $record, visibility: $visibility)';
}


}

/// @nodoc
abstract mixin class $BridgeDisplayBlockBody_SingleCopyWith<$Res> implements $BridgeDisplayBlockBodyCopyWith<$Res> {
  factory $BridgeDisplayBlockBody_SingleCopyWith(BridgeDisplayBlockBody_Single value, $Res Function(BridgeDisplayBlockBody_Single) _then) = _$BridgeDisplayBlockBody_SingleCopyWithImpl;
@useResult
$Res call({
 BridgeDisplayRecord record, BridgeSingleVisibility visibility
});




}
/// @nodoc
class _$BridgeDisplayBlockBody_SingleCopyWithImpl<$Res>
    implements $BridgeDisplayBlockBody_SingleCopyWith<$Res> {
  _$BridgeDisplayBlockBody_SingleCopyWithImpl(this._self, this._then);

  final BridgeDisplayBlockBody_Single _self;
  final $Res Function(BridgeDisplayBlockBody_Single) _then;

/// Create a copy of BridgeDisplayBlockBody
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? record = null,Object? visibility = null,}) {
  return _then(BridgeDisplayBlockBody_Single(
record: null == record ? _self.record : record // ignore: cast_nullable_to_non_nullable
as BridgeDisplayRecord,visibility: null == visibility ? _self.visibility : visibility // ignore: cast_nullable_to_non_nullable
as BridgeSingleVisibility,
  ));
}


}

/// @nodoc
mixin _$BridgeDisplayContentSource {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayContentSource);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeDisplayContentSource()';
}


}

/// @nodoc
class $BridgeDisplayContentSourceCopyWith<$Res>  {
$BridgeDisplayContentSourceCopyWith(BridgeDisplayContentSource _, $Res Function(BridgeDisplayContentSource) __);
}


/// Adds pattern-matching-related methods to [BridgeDisplayContentSource].
extension BridgeDisplayContentSourcePatterns on BridgeDisplayContentSource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeDisplayContentSource_CurrentAtom value)?  currentAtom,TResult Function( BridgeDisplayContentSource_FrozenObservation value)?  frozenObservation,TResult Function( BridgeDisplayContentSource_CompletedOriginal value)?  completedOriginal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeDisplayContentSource_CurrentAtom() when currentAtom != null:
return currentAtom(_that);case BridgeDisplayContentSource_FrozenObservation() when frozenObservation != null:
return frozenObservation(_that);case BridgeDisplayContentSource_CompletedOriginal() when completedOriginal != null:
return completedOriginal(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeDisplayContentSource_CurrentAtom value)  currentAtom,required TResult Function( BridgeDisplayContentSource_FrozenObservation value)  frozenObservation,required TResult Function( BridgeDisplayContentSource_CompletedOriginal value)  completedOriginal,}){
final _that = this;
switch (_that) {
case BridgeDisplayContentSource_CurrentAtom():
return currentAtom(_that);case BridgeDisplayContentSource_FrozenObservation():
return frozenObservation(_that);case BridgeDisplayContentSource_CompletedOriginal():
return completedOriginal(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeDisplayContentSource_CurrentAtom value)?  currentAtom,TResult? Function( BridgeDisplayContentSource_FrozenObservation value)?  frozenObservation,TResult? Function( BridgeDisplayContentSource_CompletedOriginal value)?  completedOriginal,}){
final _that = this;
switch (_that) {
case BridgeDisplayContentSource_CurrentAtom() when currentAtom != null:
return currentAtom(_that);case BridgeDisplayContentSource_FrozenObservation() when frozenObservation != null:
return frozenObservation(_that);case BridgeDisplayContentSource_CompletedOriginal() when completedOriginal != null:
return completedOriginal(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  currentAtom,TResult Function( PlatformInt64? capturedAt,  bool available)?  frozenObservation,TResult Function( String completionId)?  completedOriginal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeDisplayContentSource_CurrentAtom() when currentAtom != null:
return currentAtom();case BridgeDisplayContentSource_FrozenObservation() when frozenObservation != null:
return frozenObservation(_that.capturedAt,_that.available);case BridgeDisplayContentSource_CompletedOriginal() when completedOriginal != null:
return completedOriginal(_that.completionId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  currentAtom,required TResult Function( PlatformInt64? capturedAt,  bool available)  frozenObservation,required TResult Function( String completionId)  completedOriginal,}) {final _that = this;
switch (_that) {
case BridgeDisplayContentSource_CurrentAtom():
return currentAtom();case BridgeDisplayContentSource_FrozenObservation():
return frozenObservation(_that.capturedAt,_that.available);case BridgeDisplayContentSource_CompletedOriginal():
return completedOriginal(_that.completionId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  currentAtom,TResult? Function( PlatformInt64? capturedAt,  bool available)?  frozenObservation,TResult? Function( String completionId)?  completedOriginal,}) {final _that = this;
switch (_that) {
case BridgeDisplayContentSource_CurrentAtom() when currentAtom != null:
return currentAtom();case BridgeDisplayContentSource_FrozenObservation() when frozenObservation != null:
return frozenObservation(_that.capturedAt,_that.available);case BridgeDisplayContentSource_CompletedOriginal() when completedOriginal != null:
return completedOriginal(_that.completionId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeDisplayContentSource_CurrentAtom extends BridgeDisplayContentSource {
  const BridgeDisplayContentSource_CurrentAtom(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayContentSource_CurrentAtom);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeDisplayContentSource.currentAtom()';
}


}




/// @nodoc


class BridgeDisplayContentSource_FrozenObservation extends BridgeDisplayContentSource {
  const BridgeDisplayContentSource_FrozenObservation({this.capturedAt, required this.available}): super._();


 final  PlatformInt64? capturedAt;
 final  bool available;

/// Create a copy of BridgeDisplayContentSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDisplayContentSource_FrozenObservationCopyWith<BridgeDisplayContentSource_FrozenObservation> get copyWith => _$BridgeDisplayContentSource_FrozenObservationCopyWithImpl<BridgeDisplayContentSource_FrozenObservation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayContentSource_FrozenObservation&&(identical(other.capturedAt, capturedAt) || other.capturedAt == capturedAt)&&(identical(other.available, available) || other.available == available));
}


@override
int get hashCode {
    return Object.hash(runtimeType,capturedAt,available);
}

@override
String toString() {
    return 'BridgeDisplayContentSource.frozenObservation(capturedAt: $capturedAt, available: $available)';
}


}

/// @nodoc
abstract mixin class $BridgeDisplayContentSource_FrozenObservationCopyWith<$Res> implements $BridgeDisplayContentSourceCopyWith<$Res> {
  factory $BridgeDisplayContentSource_FrozenObservationCopyWith(BridgeDisplayContentSource_FrozenObservation value, $Res Function(BridgeDisplayContentSource_FrozenObservation) _then) = _$BridgeDisplayContentSource_FrozenObservationCopyWithImpl;
@useResult
$Res call({
 PlatformInt64? capturedAt, bool available
});




}
/// @nodoc
class _$BridgeDisplayContentSource_FrozenObservationCopyWithImpl<$Res>
    implements $BridgeDisplayContentSource_FrozenObservationCopyWith<$Res> {
  _$BridgeDisplayContentSource_FrozenObservationCopyWithImpl(this._self, this._then);

  final BridgeDisplayContentSource_FrozenObservation _self;
  final $Res Function(BridgeDisplayContentSource_FrozenObservation) _then;

/// Create a copy of BridgeDisplayContentSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? capturedAt = freezed,Object? available = null,}) {
  return _then(BridgeDisplayContentSource_FrozenObservation(
capturedAt: freezed == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeDisplayContentSource_CompletedOriginal extends BridgeDisplayContentSource {
  const BridgeDisplayContentSource_CompletedOriginal({required this.completionId}): super._();


 final  String completionId;

/// Create a copy of BridgeDisplayContentSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDisplayContentSource_CompletedOriginalCopyWith<BridgeDisplayContentSource_CompletedOriginal> get copyWith => _$BridgeDisplayContentSource_CompletedOriginalCopyWithImpl<BridgeDisplayContentSource_CompletedOriginal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayContentSource_CompletedOriginal&&(identical(other.completionId, completionId) || other.completionId == completionId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completionId);
}

@override
String toString() {
    return 'BridgeDisplayContentSource.completedOriginal(completionId: $completionId)';
}


}

/// @nodoc
abstract mixin class $BridgeDisplayContentSource_CompletedOriginalCopyWith<$Res> implements $BridgeDisplayContentSourceCopyWith<$Res> {
  factory $BridgeDisplayContentSource_CompletedOriginalCopyWith(BridgeDisplayContentSource_CompletedOriginal value, $Res Function(BridgeDisplayContentSource_CompletedOriginal) _then) = _$BridgeDisplayContentSource_CompletedOriginalCopyWithImpl;
@useResult
$Res call({
 String completionId
});




}
/// @nodoc
class _$BridgeDisplayContentSource_CompletedOriginalCopyWithImpl<$Res>
    implements $BridgeDisplayContentSource_CompletedOriginalCopyWith<$Res> {
  _$BridgeDisplayContentSource_CompletedOriginalCopyWithImpl(this._self, this._then);

  final BridgeDisplayContentSource_CompletedOriginal _self;
  final $Res Function(BridgeDisplayContentSource_CompletedOriginal) _then;

/// Create a copy of BridgeDisplayContentSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completionId = null,}) {
  return _then(BridgeDisplayContentSource_CompletedOriginal(
completionId: null == completionId ? _self.completionId : completionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeDisplayMemberWindow {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayMemberWindow);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeDisplayMemberWindow()';
}


}

/// @nodoc
class $BridgeDisplayMemberWindowCopyWith<$Res>  {
$BridgeDisplayMemberWindowCopyWith(BridgeDisplayMemberWindow _, $Res Function(BridgeDisplayMemberWindow) __);
}


/// Adds pattern-matching-related methods to [BridgeDisplayMemberWindow].
extension BridgeDisplayMemberWindowPatterns on BridgeDisplayMemberWindow {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeDisplayMemberWindow_Latest value)?  latest,TResult Function( BridgeDisplayMemberWindow_Before value)?  before,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeDisplayMemberWindow_Latest() when latest != null:
return latest(_that);case BridgeDisplayMemberWindow_Before() when before != null:
return before(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeDisplayMemberWindow_Latest value)  latest,required TResult Function( BridgeDisplayMemberWindow_Before value)  before,}){
final _that = this;
switch (_that) {
case BridgeDisplayMemberWindow_Latest():
return latest(_that);case BridgeDisplayMemberWindow_Before():
return before(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeDisplayMemberWindow_Latest value)?  latest,TResult? Function( BridgeDisplayMemberWindow_Before value)?  before,}){
final _that = this;
switch (_that) {
case BridgeDisplayMemberWindow_Latest() when latest != null:
return latest(_that);case BridgeDisplayMemberWindow_Before() when before != null:
return before(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  latest,TResult Function( BigInt memberOrder)?  before,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeDisplayMemberWindow_Latest() when latest != null:
return latest();case BridgeDisplayMemberWindow_Before() when before != null:
return before(_that.memberOrder);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  latest,required TResult Function( BigInt memberOrder)  before,}) {final _that = this;
switch (_that) {
case BridgeDisplayMemberWindow_Latest():
return latest();case BridgeDisplayMemberWindow_Before():
return before(_that.memberOrder);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  latest,TResult? Function( BigInt memberOrder)?  before,}) {final _that = this;
switch (_that) {
case BridgeDisplayMemberWindow_Latest() when latest != null:
return latest();case BridgeDisplayMemberWindow_Before() when before != null:
return before(_that.memberOrder);case _:
  return null;

}
}

}

/// @nodoc


class BridgeDisplayMemberWindow_Latest extends BridgeDisplayMemberWindow {
  const BridgeDisplayMemberWindow_Latest(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayMemberWindow_Latest);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeDisplayMemberWindow.latest()';
}


}




/// @nodoc


class BridgeDisplayMemberWindow_Before extends BridgeDisplayMemberWindow {
  const BridgeDisplayMemberWindow_Before({required this.memberOrder}): super._();


 final  BigInt memberOrder;

/// Create a copy of BridgeDisplayMemberWindow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDisplayMemberWindow_BeforeCopyWith<BridgeDisplayMemberWindow_Before> get copyWith => _$BridgeDisplayMemberWindow_BeforeCopyWithImpl<BridgeDisplayMemberWindow_Before>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayMemberWindow_Before&&(identical(other.memberOrder, memberOrder) || other.memberOrder == memberOrder));
}


@override
int get hashCode {
    return Object.hash(runtimeType,memberOrder);
}

@override
String toString() {
    return 'BridgeDisplayMemberWindow.before(memberOrder: $memberOrder)';
}


}

/// @nodoc
abstract mixin class $BridgeDisplayMemberWindow_BeforeCopyWith<$Res> implements $BridgeDisplayMemberWindowCopyWith<$Res> {
  factory $BridgeDisplayMemberWindow_BeforeCopyWith(BridgeDisplayMemberWindow_Before value, $Res Function(BridgeDisplayMemberWindow_Before) _then) = _$BridgeDisplayMemberWindow_BeforeCopyWithImpl;
@useResult
$Res call({
 BigInt memberOrder
});




}
/// @nodoc
class _$BridgeDisplayMemberWindow_BeforeCopyWithImpl<$Res>
    implements $BridgeDisplayMemberWindow_BeforeCopyWith<$Res> {
  _$BridgeDisplayMemberWindow_BeforeCopyWithImpl(this._self, this._then);

  final BridgeDisplayMemberWindow_Before _self;
  final $Res Function(BridgeDisplayMemberWindow_Before) _then;

/// Create a copy of BridgeDisplayMemberWindow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? memberOrder = null,}) {
  return _then(BridgeDisplayMemberWindow_Before(
memberOrder: null == memberOrder ? _self.memberOrder : memberOrder // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
