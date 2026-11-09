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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeWorkSummary summary,  BridgeDisplayBlockRef members)?  work,TResult Function( BridgeChatAtom atom,  String? completionId)?  single,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeDisplayBlockBody_Work() when work != null:
return work(_that.summary,_that.members);case BridgeDisplayBlockBody_Single() when single != null:
return single(_that.atom,_that.completionId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeWorkSummary summary,  BridgeDisplayBlockRef members)  work,required TResult Function( BridgeChatAtom atom,  String? completionId)  single,}) {final _that = this;
switch (_that) {
case BridgeDisplayBlockBody_Work():
return work(_that.summary,_that.members);case BridgeDisplayBlockBody_Single():
return single(_that.atom,_that.completionId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeWorkSummary summary,  BridgeDisplayBlockRef members)?  work,TResult? Function( BridgeChatAtom atom,  String? completionId)?  single,}) {final _that = this;
switch (_that) {
case BridgeDisplayBlockBody_Work() when work != null:
return work(_that.summary,_that.members);case BridgeDisplayBlockBody_Single() when single != null:
return single(_that.atom,_that.completionId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeDisplayBlockBody_Work extends BridgeDisplayBlockBody {
  const BridgeDisplayBlockBody_Work({required this.summary, required this.members}): super._();


 final  BridgeWorkSummary summary;
 final  BridgeDisplayBlockRef members;

/// Create a copy of BridgeDisplayBlockBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDisplayBlockBody_WorkCopyWith<BridgeDisplayBlockBody_Work> get copyWith => _$BridgeDisplayBlockBody_WorkCopyWithImpl<BridgeDisplayBlockBody_Work>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayBlockBody_Work&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.members, members) || other.members == members));
}


@override
int get hashCode {
    return Object.hash(runtimeType,summary,members);
}

@override
String toString() {
    return 'BridgeDisplayBlockBody.work(summary: $summary, members: $members)';
}


}

/// @nodoc
abstract mixin class $BridgeDisplayBlockBody_WorkCopyWith<$Res> implements $BridgeDisplayBlockBodyCopyWith<$Res> {
  factory $BridgeDisplayBlockBody_WorkCopyWith(BridgeDisplayBlockBody_Work value, $Res Function(BridgeDisplayBlockBody_Work) _then) = _$BridgeDisplayBlockBody_WorkCopyWithImpl;
@useResult
$Res call({
 BridgeWorkSummary summary, BridgeDisplayBlockRef members
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
@pragma('vm:prefer-inline') $Res call({Object? summary = null,Object? members = null,}) {
  return _then(BridgeDisplayBlockBody_Work(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as BridgeWorkSummary,members: null == members ? _self.members : members // ignore: cast_nullable_to_non_nullable
as BridgeDisplayBlockRef,
  ));
}


}

/// @nodoc


class BridgeDisplayBlockBody_Single extends BridgeDisplayBlockBody {
  const BridgeDisplayBlockBody_Single({required this.atom, this.completionId}): super._();


 final  BridgeChatAtom atom;
 final  String? completionId;

/// Create a copy of BridgeDisplayBlockBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDisplayBlockBody_SingleCopyWith<BridgeDisplayBlockBody_Single> get copyWith => _$BridgeDisplayBlockBody_SingleCopyWithImpl<BridgeDisplayBlockBody_Single>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDisplayBlockBody_Single&&(identical(other.atom, atom) || other.atom == atom)&&(identical(other.completionId, completionId) || other.completionId == completionId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,atom,completionId);
}

@override
String toString() {
    return 'BridgeDisplayBlockBody.single(atom: $atom, completionId: $completionId)';
}


}

/// @nodoc
abstract mixin class $BridgeDisplayBlockBody_SingleCopyWith<$Res> implements $BridgeDisplayBlockBodyCopyWith<$Res> {
  factory $BridgeDisplayBlockBody_SingleCopyWith(BridgeDisplayBlockBody_Single value, $Res Function(BridgeDisplayBlockBody_Single) _then) = _$BridgeDisplayBlockBody_SingleCopyWithImpl;
@useResult
$Res call({
 BridgeChatAtom atom, String? completionId
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
@pragma('vm:prefer-inline') $Res call({Object? atom = null,Object? completionId = freezed,}) {
  return _then(BridgeDisplayBlockBody_Single(
atom: null == atom ? _self.atom : atom // ignore: cast_nullable_to_non_nullable
as BridgeChatAtom,completionId: freezed == completionId ? _self.completionId : completionId // ignore: cast_nullable_to_non_nullable
as String?,
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
