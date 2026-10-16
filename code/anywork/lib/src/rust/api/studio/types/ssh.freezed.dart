// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ssh.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SshPasswordInput {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SshPasswordInput);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SshPasswordInput()';
}


}

/// @nodoc
class $SshPasswordInputCopyWith<$Res>  {
$SshPasswordInputCopyWith(SshPasswordInput _, $Res Function(SshPasswordInput) __);
}


/// Adds pattern-matching-related methods to [SshPasswordInput].
extension SshPasswordInputPatterns on SshPasswordInput {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SshPasswordInput_Preserve value)?  preserve,TResult Function( SshPasswordInput_Replace value)?  replace,TResult Function( SshPasswordInput_Clear value)?  clear,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SshPasswordInput_Preserve() when preserve != null:
return preserve(_that);case SshPasswordInput_Replace() when replace != null:
return replace(_that);case SshPasswordInput_Clear() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SshPasswordInput_Preserve value)  preserve,required TResult Function( SshPasswordInput_Replace value)  replace,required TResult Function( SshPasswordInput_Clear value)  clear,}){
final _that = this;
switch (_that) {
case SshPasswordInput_Preserve():
return preserve(_that);case SshPasswordInput_Replace():
return replace(_that);case SshPasswordInput_Clear():
return clear(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SshPasswordInput_Preserve value)?  preserve,TResult? Function( SshPasswordInput_Replace value)?  replace,TResult? Function( SshPasswordInput_Clear value)?  clear,}){
final _that = this;
switch (_that) {
case SshPasswordInput_Preserve() when preserve != null:
return preserve(_that);case SshPasswordInput_Replace() when replace != null:
return replace(_that);case SshPasswordInput_Clear() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  preserve,TResult Function( String value)?  replace,TResult Function()?  clear,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SshPasswordInput_Preserve() when preserve != null:
return preserve();case SshPasswordInput_Replace() when replace != null:
return replace(_that.value);case SshPasswordInput_Clear() when clear != null:
return clear();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  preserve,required TResult Function( String value)  replace,required TResult Function()  clear,}) {final _that = this;
switch (_that) {
case SshPasswordInput_Preserve():
return preserve();case SshPasswordInput_Replace():
return replace(_that.value);case SshPasswordInput_Clear():
return clear();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  preserve,TResult? Function( String value)?  replace,TResult? Function()?  clear,}) {final _that = this;
switch (_that) {
case SshPasswordInput_Preserve() when preserve != null:
return preserve();case SshPasswordInput_Replace() when replace != null:
return replace(_that.value);case SshPasswordInput_Clear() when clear != null:
return clear();case _:
  return null;

}
}

}

/// @nodoc


class SshPasswordInput_Preserve extends SshPasswordInput {
  const SshPasswordInput_Preserve(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SshPasswordInput_Preserve);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SshPasswordInput.preserve()';
}


}




/// @nodoc


class SshPasswordInput_Replace extends SshPasswordInput {
  const SshPasswordInput_Replace({required this.value}): super._();


 final  String value;

/// Create a copy of SshPasswordInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshPasswordInput_ReplaceCopyWith<SshPasswordInput_Replace> get copyWith => _$SshPasswordInput_ReplaceCopyWithImpl<SshPasswordInput_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SshPasswordInput_Replace&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'SshPasswordInput.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $SshPasswordInput_ReplaceCopyWith<$Res> implements $SshPasswordInputCopyWith<$Res> {
  factory $SshPasswordInput_ReplaceCopyWith(SshPasswordInput_Replace value, $Res Function(SshPasswordInput_Replace) _then) = _$SshPasswordInput_ReplaceCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$SshPasswordInput_ReplaceCopyWithImpl<$Res>
    implements $SshPasswordInput_ReplaceCopyWith<$Res> {
  _$SshPasswordInput_ReplaceCopyWithImpl(this._self, this._then);

  final SshPasswordInput_Replace _self;
  final $Res Function(SshPasswordInput_Replace) _then;

/// Create a copy of SshPasswordInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(SshPasswordInput_Replace(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SshPasswordInput_Clear extends SshPasswordInput {
  const SshPasswordInput_Clear(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SshPasswordInput_Clear);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SshPasswordInput.clear()';
}


}




// dart format on
