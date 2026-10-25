// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'submission_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SubmitPromptReceipt {

 String get threadId; String get inputId; int get cursor; String get requestDigest;
/// Create a copy of SubmitPromptReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubmitPromptReceiptCopyWith<SubmitPromptReceipt> get copyWith => _$SubmitPromptReceiptCopyWithImpl<SubmitPromptReceipt>(this as SubmitPromptReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SubmitPromptReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubmitPromptReceipt&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.cursor, _this.cursor) || other.cursor == _this.cursor)&&(identical(other.requestDigest, _this.requestDigest) || other.requestDigest == _this.requestDigest));
}


@override
int get hashCode {
  final _this = this as SubmitPromptReceipt;
  return Object.hash(runtimeType,_this.threadId,_this.inputId,_this.cursor,_this.requestDigest);
}

@override
String toString() {
  final _this = this as SubmitPromptReceipt;
  return 'SubmitPromptReceipt(threadId: ${_this.threadId}, inputId: ${_this.inputId}, cursor: ${_this.cursor}, requestDigest: ${_this.requestDigest})';
}


}

/// @nodoc
abstract mixin class $SubmitPromptReceiptCopyWith<$Res>  {
  factory $SubmitPromptReceiptCopyWith(SubmitPromptReceipt value, $Res Function(SubmitPromptReceipt) _then) = _$SubmitPromptReceiptCopyWithImpl;
@useResult
$Res call({
 String threadId, String inputId, int cursor, String requestDigest
});




}
/// @nodoc
class _$SubmitPromptReceiptCopyWithImpl<$Res>
    implements $SubmitPromptReceiptCopyWith<$Res> {
  _$SubmitPromptReceiptCopyWithImpl(this._self, this._then);

  final SubmitPromptReceipt _self;
  final $Res Function(SubmitPromptReceipt) _then;

/// Create a copy of SubmitPromptReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? inputId = null,Object? cursor = null,Object? requestDigest = null,}) {
  return _then(SubmitPromptReceipt(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,cursor: null == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as int,requestDigest: null == requestDigest ? _self.requestDigest : requestDigest // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SubmitPromptReceipt].
extension SubmitPromptReceiptPatterns on SubmitPromptReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubmitPromptReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubmitPromptReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubmitPromptReceipt value)  $default,){
final _that = this;
switch (_that) {
case _SubmitPromptReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubmitPromptReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _SubmitPromptReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  String inputId,  int cursor,  String requestDigest)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubmitPromptReceipt() when $default != null:
return $default(_that.threadId,_that.inputId,_that.cursor,_that.requestDigest);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  String inputId,  int cursor,  String requestDigest)  $default,) {final _that = this;
switch (_that) {
case _SubmitPromptReceipt():
return $default(_that.threadId,_that.inputId,_that.cursor,_that.requestDigest);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  String inputId,  int cursor,  String requestDigest)?  $default,) {final _that = this;
switch (_that) {
case _SubmitPromptReceipt() when $default != null:
return $default(_that.threadId,_that.inputId,_that.cursor,_that.requestDigest);case _:
  return null;

}
}

}

/// @nodoc


class _SubmitPromptReceipt implements SubmitPromptReceipt {
  const _SubmitPromptReceipt({required this.threadId, required this.inputId, required this.cursor, required this.requestDigest});


@override final  String threadId;
@override final  String inputId;
@override final  int cursor;
@override final  String requestDigest;

/// Create a copy of SubmitPromptReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubmitPromptReceiptCopyWith<_SubmitPromptReceipt> get copyWith => __$SubmitPromptReceiptCopyWithImpl<_SubmitPromptReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubmitPromptReceipt&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.cursor, cursor) || other.cursor == cursor)&&(identical(other.requestDigest, requestDigest) || other.requestDigest == requestDigest));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,inputId,cursor,requestDigest);
}

@override
String toString() {
    return 'SubmitPromptReceipt(threadId: $threadId, inputId: $inputId, cursor: $cursor, requestDigest: $requestDigest)';
}


}

/// @nodoc
abstract mixin class _$SubmitPromptReceiptCopyWith<$Res> implements $SubmitPromptReceiptCopyWith<$Res> {
  factory _$SubmitPromptReceiptCopyWith(_SubmitPromptReceipt value, $Res Function(_SubmitPromptReceipt) _then) = __$SubmitPromptReceiptCopyWithImpl;
@override @useResult
$Res call({
 String threadId, String inputId, int cursor, String requestDigest
});




}
/// @nodoc
class __$SubmitPromptReceiptCopyWithImpl<$Res>
    implements _$SubmitPromptReceiptCopyWith<$Res> {
  __$SubmitPromptReceiptCopyWithImpl(this._self, this._then);

  final _SubmitPromptReceipt _self;
  final $Res Function(_SubmitPromptReceipt) _then;

/// Create a copy of SubmitPromptReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? inputId = null,Object? cursor = null,Object? requestDigest = null,}) {
  return _then(_SubmitPromptReceipt(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,cursor: null == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as int,requestDigest: null == requestDigest ? _self.requestDigest : requestDigest // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$InputAcceptanceEvidence {

 int get acceptedSequence; String? get requestDigest; PersistedInputDisposition get disposition;
/// Create a copy of InputAcceptanceEvidence
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InputAcceptanceEvidenceCopyWith<InputAcceptanceEvidence> get copyWith => _$InputAcceptanceEvidenceCopyWithImpl<InputAcceptanceEvidence>(this as InputAcceptanceEvidence, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InputAcceptanceEvidence;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InputAcceptanceEvidence&&(identical(other.acceptedSequence, _this.acceptedSequence) || other.acceptedSequence == _this.acceptedSequence)&&(identical(other.requestDigest, _this.requestDigest) || other.requestDigest == _this.requestDigest)&&(identical(other.disposition, _this.disposition) || other.disposition == _this.disposition));
}


@override
int get hashCode {
  final _this = this as InputAcceptanceEvidence;
  return Object.hash(runtimeType,_this.acceptedSequence,_this.requestDigest,_this.disposition);
}

@override
String toString() {
  final _this = this as InputAcceptanceEvidence;
  return 'InputAcceptanceEvidence(acceptedSequence: ${_this.acceptedSequence}, requestDigest: ${_this.requestDigest}, disposition: ${_this.disposition})';
}


}

/// @nodoc
abstract mixin class $InputAcceptanceEvidenceCopyWith<$Res>  {
  factory $InputAcceptanceEvidenceCopyWith(InputAcceptanceEvidence value, $Res Function(InputAcceptanceEvidence) _then) = _$InputAcceptanceEvidenceCopyWithImpl;
@useResult
$Res call({
 int acceptedSequence, String? requestDigest, PersistedInputDisposition disposition
});




}
/// @nodoc
class _$InputAcceptanceEvidenceCopyWithImpl<$Res>
    implements $InputAcceptanceEvidenceCopyWith<$Res> {
  _$InputAcceptanceEvidenceCopyWithImpl(this._self, this._then);

  final InputAcceptanceEvidence _self;
  final $Res Function(InputAcceptanceEvidence) _then;

/// Create a copy of InputAcceptanceEvidence
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? acceptedSequence = null,Object? requestDigest = freezed,Object? disposition = null,}) {
  return _then(InputAcceptanceEvidence(
acceptedSequence: null == acceptedSequence ? _self.acceptedSequence : acceptedSequence // ignore: cast_nullable_to_non_nullable
as int,requestDigest: freezed == requestDigest ? _self.requestDigest : requestDigest // ignore: cast_nullable_to_non_nullable
as String?,disposition: null == disposition ? _self.disposition : disposition // ignore: cast_nullable_to_non_nullable
as PersistedInputDisposition,
  ));
}

}


/// Adds pattern-matching-related methods to [InputAcceptanceEvidence].
extension InputAcceptanceEvidencePatterns on InputAcceptanceEvidence {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InputAcceptanceEvidence value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InputAcceptanceEvidence() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InputAcceptanceEvidence value)  $default,){
final _that = this;
switch (_that) {
case _InputAcceptanceEvidence():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InputAcceptanceEvidence value)?  $default,){
final _that = this;
switch (_that) {
case _InputAcceptanceEvidence() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int acceptedSequence,  String? requestDigest,  PersistedInputDisposition disposition)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InputAcceptanceEvidence() when $default != null:
return $default(_that.acceptedSequence,_that.requestDigest,_that.disposition);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int acceptedSequence,  String? requestDigest,  PersistedInputDisposition disposition)  $default,) {final _that = this;
switch (_that) {
case _InputAcceptanceEvidence():
return $default(_that.acceptedSequence,_that.requestDigest,_that.disposition);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int acceptedSequence,  String? requestDigest,  PersistedInputDisposition disposition)?  $default,) {final _that = this;
switch (_that) {
case _InputAcceptanceEvidence() when $default != null:
return $default(_that.acceptedSequence,_that.requestDigest,_that.disposition);case _:
  return null;

}
}

}

/// @nodoc


class _InputAcceptanceEvidence implements InputAcceptanceEvidence {
  const _InputAcceptanceEvidence({required this.acceptedSequence, required this.requestDigest, required this.disposition});


@override final  int acceptedSequence;
@override final  String? requestDigest;
@override final  PersistedInputDisposition disposition;

/// Create a copy of InputAcceptanceEvidence
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InputAcceptanceEvidenceCopyWith<_InputAcceptanceEvidence> get copyWith => __$InputAcceptanceEvidenceCopyWithImpl<_InputAcceptanceEvidence>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InputAcceptanceEvidence&&(identical(other.acceptedSequence, acceptedSequence) || other.acceptedSequence == acceptedSequence)&&(identical(other.requestDigest, requestDigest) || other.requestDigest == requestDigest)&&(identical(other.disposition, disposition) || other.disposition == disposition));
}


@override
int get hashCode {
    return Object.hash(runtimeType,acceptedSequence,requestDigest,disposition);
}

@override
String toString() {
    return 'InputAcceptanceEvidence(acceptedSequence: $acceptedSequence, requestDigest: $requestDigest, disposition: $disposition)';
}


}

/// @nodoc
abstract mixin class _$InputAcceptanceEvidenceCopyWith<$Res> implements $InputAcceptanceEvidenceCopyWith<$Res> {
  factory _$InputAcceptanceEvidenceCopyWith(_InputAcceptanceEvidence value, $Res Function(_InputAcceptanceEvidence) _then) = __$InputAcceptanceEvidenceCopyWithImpl;
@override @useResult
$Res call({
 int acceptedSequence, String? requestDigest, PersistedInputDisposition disposition
});




}
/// @nodoc
class __$InputAcceptanceEvidenceCopyWithImpl<$Res>
    implements _$InputAcceptanceEvidenceCopyWith<$Res> {
  __$InputAcceptanceEvidenceCopyWithImpl(this._self, this._then);

  final _InputAcceptanceEvidence _self;
  final $Res Function(_InputAcceptanceEvidence) _then;

/// Create a copy of InputAcceptanceEvidence
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? acceptedSequence = null,Object? requestDigest = freezed,Object? disposition = null,}) {
  return _then(_InputAcceptanceEvidence(
acceptedSequence: null == acceptedSequence ? _self.acceptedSequence : acceptedSequence // ignore: cast_nullable_to_non_nullable
as int,requestDigest: freezed == requestDigest ? _self.requestDigest : requestDigest // ignore: cast_nullable_to_non_nullable
as String?,disposition: null == disposition ? _self.disposition : disposition // ignore: cast_nullable_to_non_nullable
as PersistedInputDisposition,
  ));
}


}

/// @nodoc
mixin _$StartNewThreadResult {

 WorkspaceThreadRecord get thread; SubmitPromptReceipt get receipt;
/// Create a copy of StartNewThreadResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartNewThreadResultCopyWith<StartNewThreadResult> get copyWith => _$StartNewThreadResultCopyWithImpl<StartNewThreadResult>(this as StartNewThreadResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartNewThreadResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartNewThreadResult&&(identical(other.thread, _this.thread) || other.thread == _this.thread)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as StartNewThreadResult;
  return Object.hash(runtimeType,_this.thread,_this.receipt);
}

@override
String toString() {
  final _this = this as StartNewThreadResult;
  return 'StartNewThreadResult(thread: ${_this.thread}, receipt: ${_this.receipt})';
}


}

/// @nodoc
abstract mixin class $StartNewThreadResultCopyWith<$Res>  {
  factory $StartNewThreadResultCopyWith(StartNewThreadResult value, $Res Function(StartNewThreadResult) _then) = _$StartNewThreadResultCopyWithImpl;
@useResult
$Res call({
 WorkspaceThreadRecord thread, SubmitPromptReceipt receipt
});


$WorkspaceThreadRecordCopyWith<$Res> get thread;$SubmitPromptReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$StartNewThreadResultCopyWithImpl<$Res>
    implements $StartNewThreadResultCopyWith<$Res> {
  _$StartNewThreadResultCopyWithImpl(this._self, this._then);

  final StartNewThreadResult _self;
  final $Res Function(StartNewThreadResult) _then;

/// Create a copy of StartNewThreadResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? thread = null,Object? receipt = null,}) {
  return _then(StartNewThreadResult(
thread: null == thread ? _self.thread : thread // ignore: cast_nullable_to_non_nullable
as WorkspaceThreadRecord,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as SubmitPromptReceipt,
  ));
}
/// Create a copy of StartNewThreadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordCopyWith<$Res> get thread {

  return $WorkspaceThreadRecordCopyWith<$Res>(_self.thread, (value) {
    return _then(_self.copyWith(thread: value));
  });
}/// Create a copy of StartNewThreadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SubmitPromptReceiptCopyWith<$Res> get receipt {

  return $SubmitPromptReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartNewThreadResult].
extension StartNewThreadResultPatterns on StartNewThreadResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartNewThreadResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartNewThreadResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartNewThreadResult value)  $default,){
final _that = this;
switch (_that) {
case _StartNewThreadResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartNewThreadResult value)?  $default,){
final _that = this;
switch (_that) {
case _StartNewThreadResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorkspaceThreadRecord thread,  SubmitPromptReceipt receipt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartNewThreadResult() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorkspaceThreadRecord thread,  SubmitPromptReceipt receipt)  $default,) {final _that = this;
switch (_that) {
case _StartNewThreadResult():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorkspaceThreadRecord thread,  SubmitPromptReceipt receipt)?  $default,) {final _that = this;
switch (_that) {
case _StartNewThreadResult() when $default != null:
return $default(_that.thread,_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class _StartNewThreadResult implements StartNewThreadResult {
  const _StartNewThreadResult({required this.thread, required this.receipt});


@override final  WorkspaceThreadRecord thread;
@override final  SubmitPromptReceipt receipt;

/// Create a copy of StartNewThreadResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartNewThreadResultCopyWith<_StartNewThreadResult> get copyWith => __$StartNewThreadResultCopyWithImpl<_StartNewThreadResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartNewThreadResult&&(identical(other.thread, thread) || other.thread == thread)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,thread,receipt);
}

@override
String toString() {
    return 'StartNewThreadResult(thread: $thread, receipt: $receipt)';
}


}

/// @nodoc
abstract mixin class _$StartNewThreadResultCopyWith<$Res> implements $StartNewThreadResultCopyWith<$Res> {
  factory _$StartNewThreadResultCopyWith(_StartNewThreadResult value, $Res Function(_StartNewThreadResult) _then) = __$StartNewThreadResultCopyWithImpl;
@override @useResult
$Res call({
 WorkspaceThreadRecord thread, SubmitPromptReceipt receipt
});


@override $WorkspaceThreadRecordCopyWith<$Res> get thread;@override $SubmitPromptReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class __$StartNewThreadResultCopyWithImpl<$Res>
    implements _$StartNewThreadResultCopyWith<$Res> {
  __$StartNewThreadResultCopyWithImpl(this._self, this._then);

  final _StartNewThreadResult _self;
  final $Res Function(_StartNewThreadResult) _then;

/// Create a copy of StartNewThreadResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? thread = null,Object? receipt = null,}) {
  return _then(_StartNewThreadResult(
thread: null == thread ? _self.thread : thread // ignore: cast_nullable_to_non_nullable
as WorkspaceThreadRecord,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as SubmitPromptReceipt,
  ));
}

/// Create a copy of StartNewThreadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordCopyWith<$Res> get thread {

  return $WorkspaceThreadRecordCopyWith<$Res>(_self.thread, (value) {
    return _then(_self.copyWith(thread: value));
  });
}/// Create a copy of StartNewThreadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SubmitPromptReceiptCopyWith<$Res> get receipt {

  return $SubmitPromptReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

// dart format on
