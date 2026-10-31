// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_activity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeActivityContentFrame {

 String get generation; BigInt get revision;
/// Create a copy of BridgeActivityContentFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityContentFrameCopyWith<BridgeActivityContentFrame> get copyWith => _$BridgeActivityContentFrameCopyWithImpl<BridgeActivityContentFrame>(this as BridgeActivityContentFrame, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeActivityContentFrame;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityContentFrame&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as BridgeActivityContentFrame;
  return Object.hash(runtimeType,_this.generation,_this.revision);
}

@override
String toString() {
  final _this = this as BridgeActivityContentFrame;
  return 'BridgeActivityContentFrame(generation: ${_this.generation}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $BridgeActivityContentFrameCopyWith<$Res>  {
  factory $BridgeActivityContentFrameCopyWith(BridgeActivityContentFrame value, $Res Function(BridgeActivityContentFrame) _then) = _$BridgeActivityContentFrameCopyWithImpl;
@useResult
$Res call({
 String generation, BigInt revision
});




}
/// @nodoc
class _$BridgeActivityContentFrameCopyWithImpl<$Res>
    implements $BridgeActivityContentFrameCopyWith<$Res> {
  _$BridgeActivityContentFrameCopyWithImpl(this._self, this._then);

  final BridgeActivityContentFrame _self;
  final $Res Function(BridgeActivityContentFrame) _then;

/// Create a copy of BridgeActivityContentFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,Object? revision = null,}) {
  return _then(_self.copyWith(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeActivityContentFrame].
extension BridgeActivityContentFramePatterns on BridgeActivityContentFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeActivityContentFrame_Begin value)?  begin,TResult Function( BridgeActivityContentFrame_Text value)?  text,TResult Function( BridgeActivityContentFrame_Commit value)?  commit,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeActivityContentFrame_Begin() when begin != null:
return begin(_that);case BridgeActivityContentFrame_Text() when text != null:
return text(_that);case BridgeActivityContentFrame_Commit() when commit != null:
return commit(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeActivityContentFrame_Begin value)  begin,required TResult Function( BridgeActivityContentFrame_Text value)  text,required TResult Function( BridgeActivityContentFrame_Commit value)  commit,}){
final _that = this;
switch (_that) {
case BridgeActivityContentFrame_Begin():
return begin(_that);case BridgeActivityContentFrame_Text():
return text(_that);case BridgeActivityContentFrame_Commit():
return commit(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeActivityContentFrame_Begin value)?  begin,TResult? Function( BridgeActivityContentFrame_Text value)?  text,TResult? Function( BridgeActivityContentFrame_Commit value)?  commit,}){
final _that = this;
switch (_that) {
case BridgeActivityContentFrame_Begin() when begin != null:
return begin(_that);case BridgeActivityContentFrame_Text() when text != null:
return text(_that);case BridgeActivityContentFrame_Commit() when commit != null:
return commit(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String generation,  BigInt? baseRevision,  BigInt revision,  BridgeThreadActivity? activity,  List<BridgeActivityPartMetadata> reasoning,  List<BridgeActivityPartMetadata> response,  List<BridgeActivityToolMetadata> tools,  BigInt totalBytes)?  begin,TResult Function( String generation,  BigInt revision,  List<BridgeActivityTextOperation> operations)?  text,TResult Function( String generation,  BigInt revision)?  commit,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeActivityContentFrame_Begin() when begin != null:
return begin(_that.generation,_that.baseRevision,_that.revision,_that.activity,_that.reasoning,_that.response,_that.tools,_that.totalBytes);case BridgeActivityContentFrame_Text() when text != null:
return text(_that.generation,_that.revision,_that.operations);case BridgeActivityContentFrame_Commit() when commit != null:
return commit(_that.generation,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String generation,  BigInt? baseRevision,  BigInt revision,  BridgeThreadActivity? activity,  List<BridgeActivityPartMetadata> reasoning,  List<BridgeActivityPartMetadata> response,  List<BridgeActivityToolMetadata> tools,  BigInt totalBytes)  begin,required TResult Function( String generation,  BigInt revision,  List<BridgeActivityTextOperation> operations)  text,required TResult Function( String generation,  BigInt revision)  commit,}) {final _that = this;
switch (_that) {
case BridgeActivityContentFrame_Begin():
return begin(_that.generation,_that.baseRevision,_that.revision,_that.activity,_that.reasoning,_that.response,_that.tools,_that.totalBytes);case BridgeActivityContentFrame_Text():
return text(_that.generation,_that.revision,_that.operations);case BridgeActivityContentFrame_Commit():
return commit(_that.generation,_that.revision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String generation,  BigInt? baseRevision,  BigInt revision,  BridgeThreadActivity? activity,  List<BridgeActivityPartMetadata> reasoning,  List<BridgeActivityPartMetadata> response,  List<BridgeActivityToolMetadata> tools,  BigInt totalBytes)?  begin,TResult? Function( String generation,  BigInt revision,  List<BridgeActivityTextOperation> operations)?  text,TResult? Function( String generation,  BigInt revision)?  commit,}) {final _that = this;
switch (_that) {
case BridgeActivityContentFrame_Begin() when begin != null:
return begin(_that.generation,_that.baseRevision,_that.revision,_that.activity,_that.reasoning,_that.response,_that.tools,_that.totalBytes);case BridgeActivityContentFrame_Text() when text != null:
return text(_that.generation,_that.revision,_that.operations);case BridgeActivityContentFrame_Commit() when commit != null:
return commit(_that.generation,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class BridgeActivityContentFrame_Begin extends BridgeActivityContentFrame {
  const BridgeActivityContentFrame_Begin({required this.generation, this.baseRevision, required this.revision, this.activity, required  List<BridgeActivityPartMetadata> reasoning, required  List<BridgeActivityPartMetadata> response, required  List<BridgeActivityToolMetadata> tools, required this.totalBytes}): _reasoning = reasoning,_response = response,_tools = tools,super._();


@override final  String generation;
 final  BigInt? baseRevision;
@override final  BigInt revision;
 final  BridgeThreadActivity? activity;
 final  List<BridgeActivityPartMetadata> _reasoning;
 List<BridgeActivityPartMetadata> get reasoning {
  if (_reasoning is EqualUnmodifiableListView) return _reasoning;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_reasoning);
}

 final  List<BridgeActivityPartMetadata> _response;
 List<BridgeActivityPartMetadata> get response {
  if (_response is EqualUnmodifiableListView) return _response;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_response);
}

 final  List<BridgeActivityToolMetadata> _tools;
 List<BridgeActivityToolMetadata> get tools {
  if (_tools is EqualUnmodifiableListView) return _tools;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tools);
}

 final  BigInt totalBytes;

/// Create a copy of BridgeActivityContentFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityContentFrame_BeginCopyWith<BridgeActivityContentFrame_Begin> get copyWith => _$BridgeActivityContentFrame_BeginCopyWithImpl<BridgeActivityContentFrame_Begin>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityContentFrame_Begin&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.activity, activity) || other.activity == activity)&&const DeepCollectionEquality().equals(other.reasoning, _reasoning)&&const DeepCollectionEquality().equals(other.response, _response)&&const DeepCollectionEquality().equals(other.tools, _tools)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,generation,baseRevision,revision,activity,const DeepCollectionEquality().hash(_reasoning),const DeepCollectionEquality().hash(_response),const DeepCollectionEquality().hash(_tools),totalBytes);
}

@override
String toString() {
    return 'BridgeActivityContentFrame.begin(generation: $generation, baseRevision: $baseRevision, revision: $revision, activity: $activity, reasoning: $reasoning, response: $response, tools: $tools, totalBytes: $totalBytes)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityContentFrame_BeginCopyWith<$Res> implements $BridgeActivityContentFrameCopyWith<$Res> {
  factory $BridgeActivityContentFrame_BeginCopyWith(BridgeActivityContentFrame_Begin value, $Res Function(BridgeActivityContentFrame_Begin) _then) = _$BridgeActivityContentFrame_BeginCopyWithImpl;
@override @useResult
$Res call({
 String generation, BigInt? baseRevision, BigInt revision, BridgeThreadActivity? activity, List<BridgeActivityPartMetadata> reasoning, List<BridgeActivityPartMetadata> response, List<BridgeActivityToolMetadata> tools, BigInt totalBytes
});




}
/// @nodoc
class _$BridgeActivityContentFrame_BeginCopyWithImpl<$Res>
    implements $BridgeActivityContentFrame_BeginCopyWith<$Res> {
  _$BridgeActivityContentFrame_BeginCopyWithImpl(this._self, this._then);

  final BridgeActivityContentFrame_Begin _self;
  final $Res Function(BridgeActivityContentFrame_Begin) _then;

/// Create a copy of BridgeActivityContentFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? baseRevision = freezed,Object? revision = null,Object? activity = freezed,Object? reasoning = null,Object? response = null,Object? tools = null,Object? totalBytes = null,}) {
  return _then(BridgeActivityContentFrame_Begin(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as String,baseRevision: freezed == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,activity: freezed == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as BridgeThreadActivity?,reasoning: null == reasoning ? _self._reasoning : reasoning // ignore: cast_nullable_to_non_nullable
as List<BridgeActivityPartMetadata>,response: null == response ? _self._response : response // ignore: cast_nullable_to_non_nullable
as List<BridgeActivityPartMetadata>,tools: null == tools ? _self._tools : tools // ignore: cast_nullable_to_non_nullable
as List<BridgeActivityToolMetadata>,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeActivityContentFrame_Text extends BridgeActivityContentFrame {
  const BridgeActivityContentFrame_Text({required this.generation, required this.revision, required  List<BridgeActivityTextOperation> operations}): _operations = operations,super._();


@override final  String generation;
@override final  BigInt revision;
 final  List<BridgeActivityTextOperation> _operations;
 List<BridgeActivityTextOperation> get operations {
  if (_operations is EqualUnmodifiableListView) return _operations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_operations);
}


/// Create a copy of BridgeActivityContentFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityContentFrame_TextCopyWith<BridgeActivityContentFrame_Text> get copyWith => _$BridgeActivityContentFrame_TextCopyWithImpl<BridgeActivityContentFrame_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityContentFrame_Text&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.revision, revision) || other.revision == revision)&&const DeepCollectionEquality().equals(other.operations, _operations));
}


@override
int get hashCode {
    return Object.hash(runtimeType,generation,revision,const DeepCollectionEquality().hash(_operations));
}

@override
String toString() {
    return 'BridgeActivityContentFrame.text(generation: $generation, revision: $revision, operations: $operations)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityContentFrame_TextCopyWith<$Res> implements $BridgeActivityContentFrameCopyWith<$Res> {
  factory $BridgeActivityContentFrame_TextCopyWith(BridgeActivityContentFrame_Text value, $Res Function(BridgeActivityContentFrame_Text) _then) = _$BridgeActivityContentFrame_TextCopyWithImpl;
@override @useResult
$Res call({
 String generation, BigInt revision, List<BridgeActivityTextOperation> operations
});




}
/// @nodoc
class _$BridgeActivityContentFrame_TextCopyWithImpl<$Res>
    implements $BridgeActivityContentFrame_TextCopyWith<$Res> {
  _$BridgeActivityContentFrame_TextCopyWithImpl(this._self, this._then);

  final BridgeActivityContentFrame_Text _self;
  final $Res Function(BridgeActivityContentFrame_Text) _then;

/// Create a copy of BridgeActivityContentFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? revision = null,Object? operations = null,}) {
  return _then(BridgeActivityContentFrame_Text(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,operations: null == operations ? _self._operations : operations // ignore: cast_nullable_to_non_nullable
as List<BridgeActivityTextOperation>,
  ));
}


}

/// @nodoc


class BridgeActivityContentFrame_Commit extends BridgeActivityContentFrame {
  const BridgeActivityContentFrame_Commit({required this.generation, required this.revision}): super._();


@override final  String generation;
@override final  BigInt revision;

/// Create a copy of BridgeActivityContentFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityContentFrame_CommitCopyWith<BridgeActivityContentFrame_Commit> get copyWith => _$BridgeActivityContentFrame_CommitCopyWithImpl<BridgeActivityContentFrame_Commit>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityContentFrame_Commit&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,generation,revision);
}

@override
String toString() {
    return 'BridgeActivityContentFrame.commit(generation: $generation, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityContentFrame_CommitCopyWith<$Res> implements $BridgeActivityContentFrameCopyWith<$Res> {
  factory $BridgeActivityContentFrame_CommitCopyWith(BridgeActivityContentFrame_Commit value, $Res Function(BridgeActivityContentFrame_Commit) _then) = _$BridgeActivityContentFrame_CommitCopyWithImpl;
@override @useResult
$Res call({
 String generation, BigInt revision
});




}
/// @nodoc
class _$BridgeActivityContentFrame_CommitCopyWithImpl<$Res>
    implements $BridgeActivityContentFrame_CommitCopyWith<$Res> {
  _$BridgeActivityContentFrame_CommitCopyWithImpl(this._self, this._then);

  final BridgeActivityContentFrame_Commit _self;
  final $Res Function(BridgeActivityContentFrame_Commit) _then;

/// Create a copy of BridgeActivityContentFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? revision = null,}) {
  return _then(BridgeActivityContentFrame_Commit(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc
mixin _$BridgeActivityTextOperation {

 BridgeActivityTextRegion get region;
/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityTextOperationCopyWith<BridgeActivityTextOperation> get copyWith => _$BridgeActivityTextOperationCopyWithImpl<BridgeActivityTextOperation>(this as BridgeActivityTextOperation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeActivityTextOperation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityTextOperation&&(identical(other.region, _this.region) || other.region == _this.region));
}


@override
int get hashCode {
  final _this = this as BridgeActivityTextOperation;
  return Object.hash(runtimeType,_this.region);
}

@override
String toString() {
  final _this = this as BridgeActivityTextOperation;
  return 'BridgeActivityTextOperation(region: ${_this.region})';
}


}

/// @nodoc
abstract mixin class $BridgeActivityTextOperationCopyWith<$Res>  {
  factory $BridgeActivityTextOperationCopyWith(BridgeActivityTextOperation value, $Res Function(BridgeActivityTextOperation) _then) = _$BridgeActivityTextOperationCopyWithImpl;
@useResult
$Res call({
 BridgeActivityTextRegion region
});


$BridgeActivityTextRegionCopyWith<$Res> get region;

}
/// @nodoc
class _$BridgeActivityTextOperationCopyWithImpl<$Res>
    implements $BridgeActivityTextOperationCopyWith<$Res> {
  _$BridgeActivityTextOperationCopyWithImpl(this._self, this._then);

  final BridgeActivityTextOperation _self;
  final $Res Function(BridgeActivityTextOperation) _then;

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? region = null,}) {
  return _then(_self.copyWith(
region: null == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as BridgeActivityTextRegion,
  ));
}
/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeActivityTextRegionCopyWith<$Res> get region {

  return $BridgeActivityTextRegionCopyWith<$Res>(_self.region, (value) {
    return _then(_self.copyWith(region: value));
  });
}
}


/// Adds pattern-matching-related methods to [BridgeActivityTextOperation].
extension BridgeActivityTextOperationPatterns on BridgeActivityTextOperation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeActivityTextOperation_Append value)?  append,TResult Function( BridgeActivityTextOperation_Replace value)?  replace,TResult Function( BridgeActivityTextOperation_Remove value)?  remove,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeActivityTextOperation_Append() when append != null:
return append(_that);case BridgeActivityTextOperation_Replace() when replace != null:
return replace(_that);case BridgeActivityTextOperation_Remove() when remove != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeActivityTextOperation_Append value)  append,required TResult Function( BridgeActivityTextOperation_Replace value)  replace,required TResult Function( BridgeActivityTextOperation_Remove value)  remove,}){
final _that = this;
switch (_that) {
case BridgeActivityTextOperation_Append():
return append(_that);case BridgeActivityTextOperation_Replace():
return replace(_that);case BridgeActivityTextOperation_Remove():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeActivityTextOperation_Append value)?  append,TResult? Function( BridgeActivityTextOperation_Replace value)?  replace,TResult? Function( BridgeActivityTextOperation_Remove value)?  remove,}){
final _that = this;
switch (_that) {
case BridgeActivityTextOperation_Append() when append != null:
return append(_that);case BridgeActivityTextOperation_Replace() when replace != null:
return replace(_that);case BridgeActivityTextOperation_Remove() when remove != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeActivityTextRegion region,  String text)?  append,TResult Function( BridgeActivityTextRegion region,  String text)?  replace,TResult Function( BridgeActivityTextRegion region)?  remove,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeActivityTextOperation_Append() when append != null:
return append(_that.region,_that.text);case BridgeActivityTextOperation_Replace() when replace != null:
return replace(_that.region,_that.text);case BridgeActivityTextOperation_Remove() when remove != null:
return remove(_that.region);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeActivityTextRegion region,  String text)  append,required TResult Function( BridgeActivityTextRegion region,  String text)  replace,required TResult Function( BridgeActivityTextRegion region)  remove,}) {final _that = this;
switch (_that) {
case BridgeActivityTextOperation_Append():
return append(_that.region,_that.text);case BridgeActivityTextOperation_Replace():
return replace(_that.region,_that.text);case BridgeActivityTextOperation_Remove():
return remove(_that.region);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeActivityTextRegion region,  String text)?  append,TResult? Function( BridgeActivityTextRegion region,  String text)?  replace,TResult? Function( BridgeActivityTextRegion region)?  remove,}) {final _that = this;
switch (_that) {
case BridgeActivityTextOperation_Append() when append != null:
return append(_that.region,_that.text);case BridgeActivityTextOperation_Replace() when replace != null:
return replace(_that.region,_that.text);case BridgeActivityTextOperation_Remove() when remove != null:
return remove(_that.region);case _:
  return null;

}
}

}

/// @nodoc


class BridgeActivityTextOperation_Append extends BridgeActivityTextOperation {
  const BridgeActivityTextOperation_Append({required this.region, required this.text}): super._();


@override final  BridgeActivityTextRegion region;
 final  String text;

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityTextOperation_AppendCopyWith<BridgeActivityTextOperation_Append> get copyWith => _$BridgeActivityTextOperation_AppendCopyWithImpl<BridgeActivityTextOperation_Append>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityTextOperation_Append&&(identical(other.region, region) || other.region == region)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,region,text);
}

@override
String toString() {
    return 'BridgeActivityTextOperation.append(region: $region, text: $text)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityTextOperation_AppendCopyWith<$Res> implements $BridgeActivityTextOperationCopyWith<$Res> {
  factory $BridgeActivityTextOperation_AppendCopyWith(BridgeActivityTextOperation_Append value, $Res Function(BridgeActivityTextOperation_Append) _then) = _$BridgeActivityTextOperation_AppendCopyWithImpl;
@override @useResult
$Res call({
 BridgeActivityTextRegion region, String text
});


@override $BridgeActivityTextRegionCopyWith<$Res> get region;

}
/// @nodoc
class _$BridgeActivityTextOperation_AppendCopyWithImpl<$Res>
    implements $BridgeActivityTextOperation_AppendCopyWith<$Res> {
  _$BridgeActivityTextOperation_AppendCopyWithImpl(this._self, this._then);

  final BridgeActivityTextOperation_Append _self;
  final $Res Function(BridgeActivityTextOperation_Append) _then;

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? region = null,Object? text = null,}) {
  return _then(BridgeActivityTextOperation_Append(
region: null == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as BridgeActivityTextRegion,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeActivityTextRegionCopyWith<$Res> get region {

  return $BridgeActivityTextRegionCopyWith<$Res>(_self.region, (value) {
    return _then(_self.copyWith(region: value));
  });
}
}

/// @nodoc


class BridgeActivityTextOperation_Replace extends BridgeActivityTextOperation {
  const BridgeActivityTextOperation_Replace({required this.region, required this.text}): super._();


@override final  BridgeActivityTextRegion region;
 final  String text;

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityTextOperation_ReplaceCopyWith<BridgeActivityTextOperation_Replace> get copyWith => _$BridgeActivityTextOperation_ReplaceCopyWithImpl<BridgeActivityTextOperation_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityTextOperation_Replace&&(identical(other.region, region) || other.region == region)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,region,text);
}

@override
String toString() {
    return 'BridgeActivityTextOperation.replace(region: $region, text: $text)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityTextOperation_ReplaceCopyWith<$Res> implements $BridgeActivityTextOperationCopyWith<$Res> {
  factory $BridgeActivityTextOperation_ReplaceCopyWith(BridgeActivityTextOperation_Replace value, $Res Function(BridgeActivityTextOperation_Replace) _then) = _$BridgeActivityTextOperation_ReplaceCopyWithImpl;
@override @useResult
$Res call({
 BridgeActivityTextRegion region, String text
});


@override $BridgeActivityTextRegionCopyWith<$Res> get region;

}
/// @nodoc
class _$BridgeActivityTextOperation_ReplaceCopyWithImpl<$Res>
    implements $BridgeActivityTextOperation_ReplaceCopyWith<$Res> {
  _$BridgeActivityTextOperation_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeActivityTextOperation_Replace _self;
  final $Res Function(BridgeActivityTextOperation_Replace) _then;

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? region = null,Object? text = null,}) {
  return _then(BridgeActivityTextOperation_Replace(
region: null == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as BridgeActivityTextRegion,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeActivityTextRegionCopyWith<$Res> get region {

  return $BridgeActivityTextRegionCopyWith<$Res>(_self.region, (value) {
    return _then(_self.copyWith(region: value));
  });
}
}

/// @nodoc


class BridgeActivityTextOperation_Remove extends BridgeActivityTextOperation {
  const BridgeActivityTextOperation_Remove({required this.region}): super._();


@override final  BridgeActivityTextRegion region;

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityTextOperation_RemoveCopyWith<BridgeActivityTextOperation_Remove> get copyWith => _$BridgeActivityTextOperation_RemoveCopyWithImpl<BridgeActivityTextOperation_Remove>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityTextOperation_Remove&&(identical(other.region, region) || other.region == region));
}


@override
int get hashCode {
    return Object.hash(runtimeType,region);
}

@override
String toString() {
    return 'BridgeActivityTextOperation.remove(region: $region)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityTextOperation_RemoveCopyWith<$Res> implements $BridgeActivityTextOperationCopyWith<$Res> {
  factory $BridgeActivityTextOperation_RemoveCopyWith(BridgeActivityTextOperation_Remove value, $Res Function(BridgeActivityTextOperation_Remove) _then) = _$BridgeActivityTextOperation_RemoveCopyWithImpl;
@override @useResult
$Res call({
 BridgeActivityTextRegion region
});


@override $BridgeActivityTextRegionCopyWith<$Res> get region;

}
/// @nodoc
class _$BridgeActivityTextOperation_RemoveCopyWithImpl<$Res>
    implements $BridgeActivityTextOperation_RemoveCopyWith<$Res> {
  _$BridgeActivityTextOperation_RemoveCopyWithImpl(this._self, this._then);

  final BridgeActivityTextOperation_Remove _self;
  final $Res Function(BridgeActivityTextOperation_Remove) _then;

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? region = null,}) {
  return _then(BridgeActivityTextOperation_Remove(
region: null == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as BridgeActivityTextRegion,
  ));
}

/// Create a copy of BridgeActivityTextOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeActivityTextRegionCopyWith<$Res> get region {

  return $BridgeActivityTextRegionCopyWith<$Res>(_self.region, (value) {
    return _then(_self.copyWith(region: value));
  });
}
}

/// @nodoc
mixin _$BridgeActivityTextRegion {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityTextRegion);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeActivityTextRegion()';
}


}

/// @nodoc
class $BridgeActivityTextRegionCopyWith<$Res>  {
$BridgeActivityTextRegionCopyWith(BridgeActivityTextRegion _, $Res Function(BridgeActivityTextRegion) __);
}


/// Adds pattern-matching-related methods to [BridgeActivityTextRegion].
extension BridgeActivityTextRegionPatterns on BridgeActivityTextRegion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeActivityTextRegion_Reasoning value)?  reasoning,TResult Function( BridgeActivityTextRegion_Response value)?  response,TResult Function( BridgeActivityTextRegion_ToolArguments value)?  toolArguments,TResult Function( BridgeActivityTextRegion_ToolOutput value)?  toolOutput,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeActivityTextRegion_Reasoning() when reasoning != null:
return reasoning(_that);case BridgeActivityTextRegion_Response() when response != null:
return response(_that);case BridgeActivityTextRegion_ToolArguments() when toolArguments != null:
return toolArguments(_that);case BridgeActivityTextRegion_ToolOutput() when toolOutput != null:
return toolOutput(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeActivityTextRegion_Reasoning value)  reasoning,required TResult Function( BridgeActivityTextRegion_Response value)  response,required TResult Function( BridgeActivityTextRegion_ToolArguments value)  toolArguments,required TResult Function( BridgeActivityTextRegion_ToolOutput value)  toolOutput,}){
final _that = this;
switch (_that) {
case BridgeActivityTextRegion_Reasoning():
return reasoning(_that);case BridgeActivityTextRegion_Response():
return response(_that);case BridgeActivityTextRegion_ToolArguments():
return toolArguments(_that);case BridgeActivityTextRegion_ToolOutput():
return toolOutput(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeActivityTextRegion_Reasoning value)?  reasoning,TResult? Function( BridgeActivityTextRegion_Response value)?  response,TResult? Function( BridgeActivityTextRegion_ToolArguments value)?  toolArguments,TResult? Function( BridgeActivityTextRegion_ToolOutput value)?  toolOutput,}){
final _that = this;
switch (_that) {
case BridgeActivityTextRegion_Reasoning() when reasoning != null:
return reasoning(_that);case BridgeActivityTextRegion_Response() when response != null:
return response(_that);case BridgeActivityTextRegion_ToolArguments() when toolArguments != null:
return toolArguments(_that);case BridgeActivityTextRegion_ToolOutput() when toolOutput != null:
return toolOutput(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String itemId)?  reasoning,TResult Function( String itemId)?  response,TResult Function( String callId)?  toolArguments,TResult Function( String callId,  String partId)?  toolOutput,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeActivityTextRegion_Reasoning() when reasoning != null:
return reasoning(_that.itemId);case BridgeActivityTextRegion_Response() when response != null:
return response(_that.itemId);case BridgeActivityTextRegion_ToolArguments() when toolArguments != null:
return toolArguments(_that.callId);case BridgeActivityTextRegion_ToolOutput() when toolOutput != null:
return toolOutput(_that.callId,_that.partId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String itemId)  reasoning,required TResult Function( String itemId)  response,required TResult Function( String callId)  toolArguments,required TResult Function( String callId,  String partId)  toolOutput,}) {final _that = this;
switch (_that) {
case BridgeActivityTextRegion_Reasoning():
return reasoning(_that.itemId);case BridgeActivityTextRegion_Response():
return response(_that.itemId);case BridgeActivityTextRegion_ToolArguments():
return toolArguments(_that.callId);case BridgeActivityTextRegion_ToolOutput():
return toolOutput(_that.callId,_that.partId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String itemId)?  reasoning,TResult? Function( String itemId)?  response,TResult? Function( String callId)?  toolArguments,TResult? Function( String callId,  String partId)?  toolOutput,}) {final _that = this;
switch (_that) {
case BridgeActivityTextRegion_Reasoning() when reasoning != null:
return reasoning(_that.itemId);case BridgeActivityTextRegion_Response() when response != null:
return response(_that.itemId);case BridgeActivityTextRegion_ToolArguments() when toolArguments != null:
return toolArguments(_that.callId);case BridgeActivityTextRegion_ToolOutput() when toolOutput != null:
return toolOutput(_that.callId,_that.partId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeActivityTextRegion_Reasoning extends BridgeActivityTextRegion {
  const BridgeActivityTextRegion_Reasoning({required this.itemId}): super._();


 final  String itemId;

/// Create a copy of BridgeActivityTextRegion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityTextRegion_ReasoningCopyWith<BridgeActivityTextRegion_Reasoning> get copyWith => _$BridgeActivityTextRegion_ReasoningCopyWithImpl<BridgeActivityTextRegion_Reasoning>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityTextRegion_Reasoning&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId);
}

@override
String toString() {
    return 'BridgeActivityTextRegion.reasoning(itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityTextRegion_ReasoningCopyWith<$Res> implements $BridgeActivityTextRegionCopyWith<$Res> {
  factory $BridgeActivityTextRegion_ReasoningCopyWith(BridgeActivityTextRegion_Reasoning value, $Res Function(BridgeActivityTextRegion_Reasoning) _then) = _$BridgeActivityTextRegion_ReasoningCopyWithImpl;
@useResult
$Res call({
 String itemId
});




}
/// @nodoc
class _$BridgeActivityTextRegion_ReasoningCopyWithImpl<$Res>
    implements $BridgeActivityTextRegion_ReasoningCopyWith<$Res> {
  _$BridgeActivityTextRegion_ReasoningCopyWithImpl(this._self, this._then);

  final BridgeActivityTextRegion_Reasoning _self;
  final $Res Function(BridgeActivityTextRegion_Reasoning) _then;

/// Create a copy of BridgeActivityTextRegion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,}) {
  return _then(BridgeActivityTextRegion_Reasoning(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeActivityTextRegion_Response extends BridgeActivityTextRegion {
  const BridgeActivityTextRegion_Response({required this.itemId}): super._();


 final  String itemId;

/// Create a copy of BridgeActivityTextRegion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityTextRegion_ResponseCopyWith<BridgeActivityTextRegion_Response> get copyWith => _$BridgeActivityTextRegion_ResponseCopyWithImpl<BridgeActivityTextRegion_Response>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityTextRegion_Response&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId);
}

@override
String toString() {
    return 'BridgeActivityTextRegion.response(itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityTextRegion_ResponseCopyWith<$Res> implements $BridgeActivityTextRegionCopyWith<$Res> {
  factory $BridgeActivityTextRegion_ResponseCopyWith(BridgeActivityTextRegion_Response value, $Res Function(BridgeActivityTextRegion_Response) _then) = _$BridgeActivityTextRegion_ResponseCopyWithImpl;
@useResult
$Res call({
 String itemId
});




}
/// @nodoc
class _$BridgeActivityTextRegion_ResponseCopyWithImpl<$Res>
    implements $BridgeActivityTextRegion_ResponseCopyWith<$Res> {
  _$BridgeActivityTextRegion_ResponseCopyWithImpl(this._self, this._then);

  final BridgeActivityTextRegion_Response _self;
  final $Res Function(BridgeActivityTextRegion_Response) _then;

/// Create a copy of BridgeActivityTextRegion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,}) {
  return _then(BridgeActivityTextRegion_Response(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeActivityTextRegion_ToolArguments extends BridgeActivityTextRegion {
  const BridgeActivityTextRegion_ToolArguments({required this.callId}): super._();


 final  String callId;

/// Create a copy of BridgeActivityTextRegion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityTextRegion_ToolArgumentsCopyWith<BridgeActivityTextRegion_ToolArguments> get copyWith => _$BridgeActivityTextRegion_ToolArgumentsCopyWithImpl<BridgeActivityTextRegion_ToolArguments>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityTextRegion_ToolArguments&&(identical(other.callId, callId) || other.callId == callId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,callId);
}

@override
String toString() {
    return 'BridgeActivityTextRegion.toolArguments(callId: $callId)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityTextRegion_ToolArgumentsCopyWith<$Res> implements $BridgeActivityTextRegionCopyWith<$Res> {
  factory $BridgeActivityTextRegion_ToolArgumentsCopyWith(BridgeActivityTextRegion_ToolArguments value, $Res Function(BridgeActivityTextRegion_ToolArguments) _then) = _$BridgeActivityTextRegion_ToolArgumentsCopyWithImpl;
@useResult
$Res call({
 String callId
});




}
/// @nodoc
class _$BridgeActivityTextRegion_ToolArgumentsCopyWithImpl<$Res>
    implements $BridgeActivityTextRegion_ToolArgumentsCopyWith<$Res> {
  _$BridgeActivityTextRegion_ToolArgumentsCopyWithImpl(this._self, this._then);

  final BridgeActivityTextRegion_ToolArguments _self;
  final $Res Function(BridgeActivityTextRegion_ToolArguments) _then;

/// Create a copy of BridgeActivityTextRegion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? callId = null,}) {
  return _then(BridgeActivityTextRegion_ToolArguments(
callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeActivityTextRegion_ToolOutput extends BridgeActivityTextRegion {
  const BridgeActivityTextRegion_ToolOutput({required this.callId, required this.partId}): super._();


 final  String callId;
 final  String partId;

/// Create a copy of BridgeActivityTextRegion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityTextRegion_ToolOutputCopyWith<BridgeActivityTextRegion_ToolOutput> get copyWith => _$BridgeActivityTextRegion_ToolOutputCopyWithImpl<BridgeActivityTextRegion_ToolOutput>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityTextRegion_ToolOutput&&(identical(other.callId, callId) || other.callId == callId)&&(identical(other.partId, partId) || other.partId == partId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,callId,partId);
}

@override
String toString() {
    return 'BridgeActivityTextRegion.toolOutput(callId: $callId, partId: $partId)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityTextRegion_ToolOutputCopyWith<$Res> implements $BridgeActivityTextRegionCopyWith<$Res> {
  factory $BridgeActivityTextRegion_ToolOutputCopyWith(BridgeActivityTextRegion_ToolOutput value, $Res Function(BridgeActivityTextRegion_ToolOutput) _then) = _$BridgeActivityTextRegion_ToolOutputCopyWithImpl;
@useResult
$Res call({
 String callId, String partId
});




}
/// @nodoc
class _$BridgeActivityTextRegion_ToolOutputCopyWithImpl<$Res>
    implements $BridgeActivityTextRegion_ToolOutputCopyWith<$Res> {
  _$BridgeActivityTextRegion_ToolOutputCopyWithImpl(this._self, this._then);

  final BridgeActivityTextRegion_ToolOutput _self;
  final $Res Function(BridgeActivityTextRegion_ToolOutput) _then;

/// Create a copy of BridgeActivityTextRegion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? callId = null,Object? partId = null,}) {
  return _then(BridgeActivityTextRegion_ToolOutput(
callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String,partId: null == partId ? _self.partId : partId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
