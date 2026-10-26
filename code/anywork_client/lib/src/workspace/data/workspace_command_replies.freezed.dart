// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workspace_command_replies.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RenameThreadCommandReply {

 WorkspaceThreadRecord get thread; CommitReceipt get receipt;
/// Create a copy of RenameThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RenameThreadCommandReplyCopyWith<RenameThreadCommandReply> get copyWith => _$RenameThreadCommandReplyCopyWithImpl<RenameThreadCommandReply>(this as RenameThreadCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RenameThreadCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RenameThreadCommandReply&&(identical(other.thread, _this.thread) || other.thread == _this.thread)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as RenameThreadCommandReply;
  return Object.hash(runtimeType,_this.thread,_this.receipt);
}



}

/// @nodoc
abstract mixin class $RenameThreadCommandReplyCopyWith<$Res>  {
  factory $RenameThreadCommandReplyCopyWith(RenameThreadCommandReply value, $Res Function(RenameThreadCommandReply) _then) = _$RenameThreadCommandReplyCopyWithImpl;
@useResult
$Res call({
 WorkspaceThreadRecord thread, CommitReceipt receipt
});


$WorkspaceThreadRecordCopyWith<$Res> get thread;$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$RenameThreadCommandReplyCopyWithImpl<$Res>
    implements $RenameThreadCommandReplyCopyWith<$Res> {
  _$RenameThreadCommandReplyCopyWithImpl(this._self, this._then);

  final RenameThreadCommandReply _self;
  final $Res Function(RenameThreadCommandReply) _then;

/// Create a copy of RenameThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? thread = null,Object? receipt = null,}) {
  return _then(RenameThreadCommandReply(
thread: null == thread ? _self.thread : thread // ignore: cast_nullable_to_non_nullable
as WorkspaceThreadRecord,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of RenameThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordCopyWith<$Res> get thread {

  return $WorkspaceThreadRecordCopyWith<$Res>(_self.thread, (value) {
    return _then(_self.copyWith(thread: value));
  });
}/// Create a copy of RenameThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [RenameThreadCommandReply].
extension RenameThreadCommandReplyPatterns on RenameThreadCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RenameThreadCommandReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RenameThreadCommandReply() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RenameThreadCommandReply value)  $default,){
final _that = this;
switch (_that) {
case _RenameThreadCommandReply():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RenameThreadCommandReply value)?  $default,){
final _that = this;
switch (_that) {
case _RenameThreadCommandReply() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorkspaceThreadRecord thread,  CommitReceipt receipt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RenameThreadCommandReply() when $default != null:
return $default(_that.thread,_that.receipt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorkspaceThreadRecord thread,  CommitReceipt receipt)  $default,) {final _that = this;
switch (_that) {
case _RenameThreadCommandReply():
return $default(_that.thread,_that.receipt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorkspaceThreadRecord thread,  CommitReceipt receipt)?  $default,) {final _that = this;
switch (_that) {
case _RenameThreadCommandReply() when $default != null:
return $default(_that.thread,_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class _RenameThreadCommandReply implements RenameThreadCommandReply {
  const _RenameThreadCommandReply({required this.thread, required this.receipt});


@override final  WorkspaceThreadRecord thread;
@override final  CommitReceipt receipt;

/// Create a copy of RenameThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RenameThreadCommandReplyCopyWith<_RenameThreadCommandReply> get copyWith => __$RenameThreadCommandReplyCopyWithImpl<_RenameThreadCommandReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RenameThreadCommandReply&&(identical(other.thread, thread) || other.thread == thread)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,thread,receipt);
}



}

/// @nodoc
abstract mixin class _$RenameThreadCommandReplyCopyWith<$Res> implements $RenameThreadCommandReplyCopyWith<$Res> {
  factory _$RenameThreadCommandReplyCopyWith(_RenameThreadCommandReply value, $Res Function(_RenameThreadCommandReply) _then) = __$RenameThreadCommandReplyCopyWithImpl;
@override @useResult
$Res call({
 WorkspaceThreadRecord thread, CommitReceipt receipt
});


@override $WorkspaceThreadRecordCopyWith<$Res> get thread;@override $CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class __$RenameThreadCommandReplyCopyWithImpl<$Res>
    implements _$RenameThreadCommandReplyCopyWith<$Res> {
  __$RenameThreadCommandReplyCopyWithImpl(this._self, this._then);

  final _RenameThreadCommandReply _self;
  final $Res Function(_RenameThreadCommandReply) _then;

/// Create a copy of RenameThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? thread = null,Object? receipt = null,}) {
  return _then(_RenameThreadCommandReply(
thread: null == thread ? _self.thread : thread // ignore: cast_nullable_to_non_nullable
as WorkspaceThreadRecord,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}

/// Create a copy of RenameThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordCopyWith<$Res> get thread {

  return $WorkspaceThreadRecordCopyWith<$Res>(_self.thread, (value) {
    return _then(_self.copyWith(thread: value));
  });
}/// Create a copy of RenameThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

/// @nodoc
mixin _$ArchiveThreadCommandReply {

 ArchiveThreadResult get result; CommitReceipt get receipt;
/// Create a copy of ArchiveThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArchiveThreadCommandReplyCopyWith<ArchiveThreadCommandReply> get copyWith => _$ArchiveThreadCommandReplyCopyWithImpl<ArchiveThreadCommandReply>(this as ArchiveThreadCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ArchiveThreadCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArchiveThreadCommandReply&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as ArchiveThreadCommandReply;
  return Object.hash(runtimeType,_this.result,_this.receipt);
}



}

/// @nodoc
abstract mixin class $ArchiveThreadCommandReplyCopyWith<$Res>  {
  factory $ArchiveThreadCommandReplyCopyWith(ArchiveThreadCommandReply value, $Res Function(ArchiveThreadCommandReply) _then) = _$ArchiveThreadCommandReplyCopyWithImpl;
@useResult
$Res call({
 ArchiveThreadResult result, CommitReceipt receipt
});


$ArchiveThreadResultCopyWith<$Res> get result;$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$ArchiveThreadCommandReplyCopyWithImpl<$Res>
    implements $ArchiveThreadCommandReplyCopyWith<$Res> {
  _$ArchiveThreadCommandReplyCopyWithImpl(this._self, this._then);

  final ArchiveThreadCommandReply _self;
  final $Res Function(ArchiveThreadCommandReply) _then;

/// Create a copy of ArchiveThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? result = null,Object? receipt = null,}) {
  return _then(ArchiveThreadCommandReply(
result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as ArchiveThreadResult,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of ArchiveThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ArchiveThreadResultCopyWith<$Res> get result {

  return $ArchiveThreadResultCopyWith<$Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of ArchiveThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [ArchiveThreadCommandReply].
extension ArchiveThreadCommandReplyPatterns on ArchiveThreadCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArchiveThreadCommandReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArchiveThreadCommandReply() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArchiveThreadCommandReply value)  $default,){
final _that = this;
switch (_that) {
case _ArchiveThreadCommandReply():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArchiveThreadCommandReply value)?  $default,){
final _that = this;
switch (_that) {
case _ArchiveThreadCommandReply() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ArchiveThreadResult result,  CommitReceipt receipt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArchiveThreadCommandReply() when $default != null:
return $default(_that.result,_that.receipt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ArchiveThreadResult result,  CommitReceipt receipt)  $default,) {final _that = this;
switch (_that) {
case _ArchiveThreadCommandReply():
return $default(_that.result,_that.receipt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ArchiveThreadResult result,  CommitReceipt receipt)?  $default,) {final _that = this;
switch (_that) {
case _ArchiveThreadCommandReply() when $default != null:
return $default(_that.result,_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class _ArchiveThreadCommandReply implements ArchiveThreadCommandReply {
  const _ArchiveThreadCommandReply({required this.result, required this.receipt});


@override final  ArchiveThreadResult result;
@override final  CommitReceipt receipt;

/// Create a copy of ArchiveThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArchiveThreadCommandReplyCopyWith<_ArchiveThreadCommandReply> get copyWith => __$ArchiveThreadCommandReplyCopyWithImpl<_ArchiveThreadCommandReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArchiveThreadCommandReply&&(identical(other.result, result) || other.result == result)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,result,receipt);
}



}

/// @nodoc
abstract mixin class _$ArchiveThreadCommandReplyCopyWith<$Res> implements $ArchiveThreadCommandReplyCopyWith<$Res> {
  factory _$ArchiveThreadCommandReplyCopyWith(_ArchiveThreadCommandReply value, $Res Function(_ArchiveThreadCommandReply) _then) = __$ArchiveThreadCommandReplyCopyWithImpl;
@override @useResult
$Res call({
 ArchiveThreadResult result, CommitReceipt receipt
});


@override $ArchiveThreadResultCopyWith<$Res> get result;@override $CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class __$ArchiveThreadCommandReplyCopyWithImpl<$Res>
    implements _$ArchiveThreadCommandReplyCopyWith<$Res> {
  __$ArchiveThreadCommandReplyCopyWithImpl(this._self, this._then);

  final _ArchiveThreadCommandReply _self;
  final $Res Function(_ArchiveThreadCommandReply) _then;

/// Create a copy of ArchiveThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? result = null,Object? receipt = null,}) {
  return _then(_ArchiveThreadCommandReply(
result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as ArchiveThreadResult,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}

/// Create a copy of ArchiveThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ArchiveThreadResultCopyWith<$Res> get result {

  return $ArchiveThreadResultCopyWith<$Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of ArchiveThreadCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

// dart format on
