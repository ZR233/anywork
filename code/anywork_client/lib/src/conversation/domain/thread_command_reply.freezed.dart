// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_command_reply.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadModelRouteCommandReply {


/// Create a copy of ThreadModelRouteCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadModelRouteCommandReplyCopyWith<ThreadModelRouteCommandReply> get copyWith => _$ThreadModelRouteCommandReplyCopyWithImpl<ThreadModelRouteCommandReply>(this as ThreadModelRouteCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadModelRouteCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadModelRouteCommandReply&&(identical(other.runtime, _this.runtime) || other.runtime == _this.runtime)&&(identical(other.settings, _this.settings) || other.settings == _this.settings)&&(identical(other.modeDefaultSaved, _this.modeDefaultSaved) || other.modeDefaultSaved == _this.modeDefaultSaved)&&(identical(other.warning, _this.warning) || other.warning == _this.warning)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as ThreadModelRouteCommandReply;
  return Object.hash(runtimeType,_this.runtime,_this.settings,_this.modeDefaultSaved,_this.warning,_this.receipt);
}



}

/// @nodoc
abstract mixin class $ThreadModelRouteCommandReplyCopyWith<$Res>  {
  factory $ThreadModelRouteCommandReplyCopyWith(ThreadModelRouteCommandReply value, $Res Function(ThreadModelRouteCommandReply) _then) = _$ThreadModelRouteCommandReplyCopyWithImpl;
@useResult
$Res call({
 ThreadRuntimeSnapshot runtime, ThreadSettingsSnapshot settings, bool modeDefaultSaved, String? warning, CommitReceipt receipt
});


$ThreadRuntimeSnapshotCopyWith<$Res> get runtime;$ThreadSettingsSnapshotCopyWith<$Res> get settings;$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$ThreadModelRouteCommandReplyCopyWithImpl<$Res>
    implements $ThreadModelRouteCommandReplyCopyWith<$Res> {
  _$ThreadModelRouteCommandReplyCopyWithImpl(this._self, this._then);

  final ThreadModelRouteCommandReply _self;
  final $Res Function(ThreadModelRouteCommandReply) _then;

/// Create a copy of ThreadModelRouteCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? runtime = null,Object? settings = null,Object? modeDefaultSaved = null,Object? warning = freezed,Object? receipt = null,}) {
  return _then(ThreadModelRouteCommandReply(
runtime: null == runtime ? _self.runtime : runtime // ignore: cast_nullable_to_non_nullable
as ThreadRuntimeSnapshot,settings: null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as ThreadSettingsSnapshot,modeDefaultSaved: null == modeDefaultSaved ? _self.modeDefaultSaved : modeDefaultSaved // ignore: cast_nullable_to_non_nullable
as bool,warning: freezed == warning ? _self.warning : warning // ignore: cast_nullable_to_non_nullable
as String?,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of ThreadModelRouteCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadRuntimeSnapshotCopyWith<$Res> get runtime {

  return $ThreadRuntimeSnapshotCopyWith<$Res>(_self.runtime, (value) {
    return _then(_self.copyWith(runtime: value));
  });
}/// Create a copy of ThreadModelRouteCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadSettingsSnapshotCopyWith<$Res> get settings {

  return $ThreadSettingsSnapshotCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}/// Create a copy of ThreadModelRouteCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadModelRouteCommandReply].
extension ThreadModelRouteCommandReplyPatterns on ThreadModelRouteCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$InteractionCommandReply {


/// Create a copy of InteractionCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionCommandReplyCopyWith<InteractionCommandReply> get copyWith => _$InteractionCommandReplyCopyWithImpl<InteractionCommandReply>(this as InteractionCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionCommandReply&&(identical(other.interaction, _this.interaction) || other.interaction == _this.interaction)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as InteractionCommandReply;
  return Object.hash(runtimeType,_this.interaction,_this.receipt);
}



}

/// @nodoc
abstract mixin class $InteractionCommandReplyCopyWith<$Res>  {
  factory $InteractionCommandReplyCopyWith(InteractionCommandReply value, $Res Function(InteractionCommandReply) _then) = _$InteractionCommandReplyCopyWithImpl;
@useResult
$Res call({
 InteractionSnapshot interaction, CommitReceipt receipt
});


$InteractionSnapshotCopyWith<$Res> get interaction;$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$InteractionCommandReplyCopyWithImpl<$Res>
    implements $InteractionCommandReplyCopyWith<$Res> {
  _$InteractionCommandReplyCopyWithImpl(this._self, this._then);

  final InteractionCommandReply _self;
  final $Res Function(InteractionCommandReply) _then;

/// Create a copy of InteractionCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? interaction = null,Object? receipt = null,}) {
  return _then(InteractionCommandReply(
interaction: null == interaction ? _self.interaction : interaction // ignore: cast_nullable_to_non_nullable
as InteractionSnapshot,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of InteractionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionSnapshotCopyWith<$Res> get interaction {

  return $InteractionSnapshotCopyWith<$Res>(_self.interaction, (value) {
    return _then(_self.copyWith(interaction: value));
  });
}/// Create a copy of InteractionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionCommandReply].
extension InteractionCommandReplyPatterns on InteractionCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

// dart format on
