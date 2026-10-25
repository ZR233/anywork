// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timeline_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StudioTimelineItemSource {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineItemSource);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $StudioTimelineItemSourceCopyWith<$Res>  {
$StudioTimelineItemSourceCopyWith(StudioTimelineItemSource _, $Res Function(StudioTimelineItemSource) __);
}


/// Adds pattern-matching-related methods to [StudioTimelineItemSource].
extension StudioTimelineItemSourcePatterns on StudioTimelineItemSource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StudioTimelineContentSource value)?  content,TResult Function( StudioTimelineRecoverySource value)?  modelRecovery,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StudioTimelineContentSource() when content != null:
return content(_that);case StudioTimelineRecoverySource() when modelRecovery != null:
return modelRecovery(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StudioTimelineContentSource value)  content,required TResult Function( StudioTimelineRecoverySource value)  modelRecovery,}){
final _that = this;
switch (_that) {
case StudioTimelineContentSource():
return content(_that);case StudioTimelineRecoverySource():
return modelRecovery(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StudioTimelineContentSource value)?  content,TResult? Function( StudioTimelineRecoverySource value)?  modelRecovery,}){
final _that = this;
switch (_that) {
case StudioTimelineContentSource() when content != null:
return content(_that);case StudioTimelineRecoverySource() when modelRecovery != null:
return modelRecovery(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  content,TResult Function( String attemptId,  StudioTimelineRecoveryNotice notice)?  modelRecovery,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StudioTimelineContentSource() when content != null:
return content();case StudioTimelineRecoverySource() when modelRecovery != null:
return modelRecovery(_that.attemptId,_that.notice);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  content,required TResult Function( String attemptId,  StudioTimelineRecoveryNotice notice)  modelRecovery,}) {final _that = this;
switch (_that) {
case StudioTimelineContentSource():
return content();case StudioTimelineRecoverySource():
return modelRecovery(_that.attemptId,_that.notice);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  content,TResult? Function( String attemptId,  StudioTimelineRecoveryNotice notice)?  modelRecovery,}) {final _that = this;
switch (_that) {
case StudioTimelineContentSource() when content != null:
return content();case StudioTimelineRecoverySource() when modelRecovery != null:
return modelRecovery(_that.attemptId,_that.notice);case _:
  return null;

}
}

}

/// @nodoc


class StudioTimelineContentSource extends StudioTimelineItemSource {
  const StudioTimelineContentSource(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineContentSource);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class StudioTimelineRecoverySource extends StudioTimelineItemSource {
  const StudioTimelineRecoverySource({required this.attemptId, required this.notice}): super._();


 final  String attemptId;
 final  StudioTimelineRecoveryNotice notice;

/// Create a copy of StudioTimelineItemSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineRecoverySourceCopyWith<StudioTimelineRecoverySource> get copyWith => _$StudioTimelineRecoverySourceCopyWithImpl<StudioTimelineRecoverySource>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineRecoverySource&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.notice, notice) || other.notice == notice));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,notice);
}



}

/// @nodoc
abstract mixin class $StudioTimelineRecoverySourceCopyWith<$Res> implements $StudioTimelineItemSourceCopyWith<$Res> {
  factory $StudioTimelineRecoverySourceCopyWith(StudioTimelineRecoverySource value, $Res Function(StudioTimelineRecoverySource) _then) = _$StudioTimelineRecoverySourceCopyWithImpl;
@useResult
$Res call({
 String attemptId, StudioTimelineRecoveryNotice notice
});




}
/// @nodoc
class _$StudioTimelineRecoverySourceCopyWithImpl<$Res>
    implements $StudioTimelineRecoverySourceCopyWith<$Res> {
  _$StudioTimelineRecoverySourceCopyWithImpl(this._self, this._then);

  final StudioTimelineRecoverySource _self;
  final $Res Function(StudioTimelineRecoverySource) _then;

/// Create a copy of StudioTimelineItemSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? notice = null,}) {
  return _then(StudioTimelineRecoverySource(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,notice: null == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as StudioTimelineRecoveryNotice,
  ));
}


}

/// @nodoc
mixin _$StudioTimelineDetailRef {

 ThreadContentFieldView get field; int get revision; int get totalBytes; int get previewBytes;
/// Create a copy of StudioTimelineDetailRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineDetailRefCopyWith<StudioTimelineDetailRef> get copyWith => _$StudioTimelineDetailRefCopyWithImpl<StudioTimelineDetailRef>(this as StudioTimelineDetailRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioTimelineDetailRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineDetailRef&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.totalBytes, _this.totalBytes) || other.totalBytes == _this.totalBytes)&&(identical(other.previewBytes, _this.previewBytes) || other.previewBytes == _this.previewBytes));
}


@override
int get hashCode {
  final _this = this as StudioTimelineDetailRef;
  return Object.hash(runtimeType,_this.field,_this.revision,_this.totalBytes,_this.previewBytes);
}



}

/// @nodoc
abstract mixin class $StudioTimelineDetailRefCopyWith<$Res>  {
  factory $StudioTimelineDetailRefCopyWith(StudioTimelineDetailRef value, $Res Function(StudioTimelineDetailRef) _then) = _$StudioTimelineDetailRefCopyWithImpl;
@useResult
$Res call({
 ThreadContentFieldView field, int revision, int totalBytes, int previewBytes
});


$ThreadContentFieldViewCopyWith<$Res> get field;

}
/// @nodoc
class _$StudioTimelineDetailRefCopyWithImpl<$Res>
    implements $StudioTimelineDetailRefCopyWith<$Res> {
  _$StudioTimelineDetailRefCopyWithImpl(this._self, this._then);

  final StudioTimelineDetailRef _self;
  final $Res Function(StudioTimelineDetailRef) _then;

/// Create a copy of StudioTimelineDetailRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field = null,Object? revision = null,Object? totalBytes = null,Object? previewBytes = null,}) {
  return _then(StudioTimelineDetailRef(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,previewBytes: null == previewBytes ? _self.previewBytes : previewBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of StudioTimelineDetailRef
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}
}


/// Adds pattern-matching-related methods to [StudioTimelineDetailRef].
extension StudioTimelineDetailRefPatterns on StudioTimelineDetailRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StudioTimelineDetailRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StudioTimelineDetailRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StudioTimelineDetailRef value)  $default,){
final _that = this;
switch (_that) {
case _StudioTimelineDetailRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StudioTimelineDetailRef value)?  $default,){
final _that = this;
switch (_that) {
case _StudioTimelineDetailRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadContentFieldView field,  int revision,  int totalBytes,  int previewBytes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StudioTimelineDetailRef() when $default != null:
return $default(_that.field,_that.revision,_that.totalBytes,_that.previewBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadContentFieldView field,  int revision,  int totalBytes,  int previewBytes)  $default,) {final _that = this;
switch (_that) {
case _StudioTimelineDetailRef():
return $default(_that.field,_that.revision,_that.totalBytes,_that.previewBytes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadContentFieldView field,  int revision,  int totalBytes,  int previewBytes)?  $default,) {final _that = this;
switch (_that) {
case _StudioTimelineDetailRef() when $default != null:
return $default(_that.field,_that.revision,_that.totalBytes,_that.previewBytes);case _:
  return null;

}
}

}

/// @nodoc


class _StudioTimelineDetailRef extends StudioTimelineDetailRef {
  const _StudioTimelineDetailRef({required this.field, required this.revision, required this.totalBytes, required this.previewBytes}): super._();


@override final  ThreadContentFieldView field;
@override final  int revision;
@override final  int totalBytes;
@override final  int previewBytes;

/// Create a copy of StudioTimelineDetailRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioTimelineDetailRefCopyWith<_StudioTimelineDetailRef> get copyWith => __$StudioTimelineDetailRefCopyWithImpl<_StudioTimelineDetailRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioTimelineDetailRef&&(identical(other.field, field) || other.field == field)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.previewBytes, previewBytes) || other.previewBytes == previewBytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field,revision,totalBytes,previewBytes);
}



}

/// @nodoc
abstract mixin class _$StudioTimelineDetailRefCopyWith<$Res> implements $StudioTimelineDetailRefCopyWith<$Res> {
  factory _$StudioTimelineDetailRefCopyWith(_StudioTimelineDetailRef value, $Res Function(_StudioTimelineDetailRef) _then) = __$StudioTimelineDetailRefCopyWithImpl;
@override @useResult
$Res call({
 ThreadContentFieldView field, int revision, int totalBytes, int previewBytes
});


@override $ThreadContentFieldViewCopyWith<$Res> get field;

}
/// @nodoc
class __$StudioTimelineDetailRefCopyWithImpl<$Res>
    implements _$StudioTimelineDetailRefCopyWith<$Res> {
  __$StudioTimelineDetailRefCopyWithImpl(this._self, this._then);

  final _StudioTimelineDetailRef _self;
  final $Res Function(_StudioTimelineDetailRef) _then;

/// Create a copy of StudioTimelineDetailRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field = null,Object? revision = null,Object? totalBytes = null,Object? previewBytes = null,}) {
  return _then(_StudioTimelineDetailRef(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,previewBytes: null == previewBytes ? _self.previewBytes : previewBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of StudioTimelineDetailRef
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}
}

/// @nodoc
mixin _$StudioTimelineItem {


/// Create a copy of StudioTimelineItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineItemCopyWith<StudioTimelineItem> get copyWith => _$StudioTimelineItemCopyWithImpl<StudioTimelineItem>(this as StudioTimelineItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioTimelineItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineItem&&(identical(other.item, _this.item) || other.item == _this.item)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.saved, _this.saved) || other.saved == _this.saved)&&(identical(other.lifecycle, _this.lifecycle) || other.lifecycle == _this.lifecycle)&&(identical(other.omittedBytes, _this.omittedBytes) || other.omittedBytes == _this.omittedBytes)&&const DeepCollectionEquality().equals(other.details, _this.details));
}


@override
int get hashCode {
  final _this = this as StudioTimelineItem;
  return Object.hash(runtimeType,_this.item,_this.source,_this.saved,_this.lifecycle,_this.omittedBytes,const DeepCollectionEquality().hash(_this.details));
}



}

/// @nodoc
abstract mixin class $StudioTimelineItemCopyWith<$Res>  {
  factory $StudioTimelineItemCopyWith(StudioTimelineItem value, $Res Function(StudioTimelineItem) _then) = _$StudioTimelineItemCopyWithImpl;
@useResult
$Res call({
 ThreadItemView item, StudioTimelineItemSource source, bool saved, StudioTimelineLifecycle lifecycle, int omittedBytes, List<StudioTimelineDetailRef> details
});


$ThreadItemViewCopyWith<$Res> get item;$StudioTimelineItemSourceCopyWith<$Res> get source;

}
/// @nodoc
class _$StudioTimelineItemCopyWithImpl<$Res>
    implements $StudioTimelineItemCopyWith<$Res> {
  _$StudioTimelineItemCopyWithImpl(this._self, this._then);

  final StudioTimelineItem _self;
  final $Res Function(StudioTimelineItem) _then;

/// Create a copy of StudioTimelineItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? item = null,Object? source = null,Object? saved = null,Object? lifecycle = null,Object? omittedBytes = null,Object? details = null,}) {
  return _then(StudioTimelineItem(
item: null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as ThreadItemView,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as StudioTimelineItemSource,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as StudioTimelineLifecycle,omittedBytes: null == omittedBytes ? _self.omittedBytes : omittedBytes // ignore: cast_nullable_to_non_nullable
as int,details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as List<StudioTimelineDetailRef>,
  ));
}
/// Create a copy of StudioTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadItemViewCopyWith<$Res> get item {

  return $ThreadItemViewCopyWith<$Res>(_self.item, (value) {
    return _then(_self.copyWith(item: value));
  });
}/// Create a copy of StudioTimelineItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelineItemSourceCopyWith<$Res> get source {

  return $StudioTimelineItemSourceCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}


/// Adds pattern-matching-related methods to [StudioTimelineItem].
extension StudioTimelineItemPatterns on StudioTimelineItem {
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
mixin _$StudioTimelineBaseline {


/// Create a copy of StudioTimelineBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineBaselineCopyWith<StudioTimelineBaseline> get copyWith => _$StudioTimelineBaselineCopyWithImpl<StudioTimelineBaseline>(this as StudioTimelineBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioTimelineBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineBaseline&&(identical(other.subscriptionId, _this.subscriptionId) || other.subscriptionId == _this.subscriptionId)&&(identical(other.version, _this.version) || other.version == _this.version)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.before, _this.before) || other.before == _this.before)&&(identical(other.hasOlder, _this.hasOlder) || other.hasOlder == _this.hasOlder));
}


@override
int get hashCode {
  final _this = this as StudioTimelineBaseline;
  return Object.hash(runtimeType,_this.subscriptionId,_this.version,const DeepCollectionEquality().hash(_this.items),_this.before,_this.hasOlder);
}



}

/// @nodoc
abstract mixin class $StudioTimelineBaselineCopyWith<$Res>  {
  factory $StudioTimelineBaselineCopyWith(StudioTimelineBaseline value, $Res Function(StudioTimelineBaseline) _then) = _$StudioTimelineBaselineCopyWithImpl;
@useResult
$Res call({
 String subscriptionId, int version, List<StudioTimelineItem> items, String? before, bool hasOlder
});




}
/// @nodoc
class _$StudioTimelineBaselineCopyWithImpl<$Res>
    implements $StudioTimelineBaselineCopyWith<$Res> {
  _$StudioTimelineBaselineCopyWithImpl(this._self, this._then);

  final StudioTimelineBaseline _self;
  final $Res Function(StudioTimelineBaseline) _then;

/// Create a copy of StudioTimelineBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? subscriptionId = null,Object? version = null,Object? items = null,Object? before = freezed,Object? hasOlder = null,}) {
  return _then(StudioTimelineBaseline(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<StudioTimelineItem>,before: freezed == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as String?,hasOlder: null == hasOlder ? _self.hasOlder : hasOlder // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [StudioTimelineBaseline].
extension StudioTimelineBaselinePatterns on StudioTimelineBaseline {
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
mixin _$StudioTimelinePage {


/// Create a copy of StudioTimelinePage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelinePageCopyWith<StudioTimelinePage> get copyWith => _$StudioTimelinePageCopyWithImpl<StudioTimelinePage>(this as StudioTimelinePage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioTimelinePage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelinePage&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.before, _this.before) || other.before == _this.before)&&(identical(other.hasOlder, _this.hasOlder) || other.hasOlder == _this.hasOlder));
}


@override
int get hashCode {
  final _this = this as StudioTimelinePage;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.items),_this.before,_this.hasOlder);
}



}

/// @nodoc
abstract mixin class $StudioTimelinePageCopyWith<$Res>  {
  factory $StudioTimelinePageCopyWith(StudioTimelinePage value, $Res Function(StudioTimelinePage) _then) = _$StudioTimelinePageCopyWithImpl;
@useResult
$Res call({
 List<StudioTimelineItem> items, String? before, bool hasOlder
});




}
/// @nodoc
class _$StudioTimelinePageCopyWithImpl<$Res>
    implements $StudioTimelinePageCopyWith<$Res> {
  _$StudioTimelinePageCopyWithImpl(this._self, this._then);

  final StudioTimelinePage _self;
  final $Res Function(StudioTimelinePage) _then;

/// Create a copy of StudioTimelinePage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? before = freezed,Object? hasOlder = null,}) {
  return _then(StudioTimelinePage(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<StudioTimelineItem>,before: freezed == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as String?,hasOlder: null == hasOlder ? _self.hasOlder : hasOlder // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [StudioTimelinePage].
extension StudioTimelinePagePatterns on StudioTimelinePage {
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
mixin _$StudioFieldUpdateView {

 ThreadContentFieldView get field; ThreadFieldChangeView get change; int get totalBytes; int get previewBytes;
/// Create a copy of StudioFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioFieldUpdateViewCopyWith<StudioFieldUpdateView> get copyWith => _$StudioFieldUpdateViewCopyWithImpl<StudioFieldUpdateView>(this as StudioFieldUpdateView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioFieldUpdateView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioFieldUpdateView&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.change, _this.change) || other.change == _this.change)&&(identical(other.totalBytes, _this.totalBytes) || other.totalBytes == _this.totalBytes)&&(identical(other.previewBytes, _this.previewBytes) || other.previewBytes == _this.previewBytes));
}


@override
int get hashCode {
  final _this = this as StudioFieldUpdateView;
  return Object.hash(runtimeType,_this.field,_this.change,_this.totalBytes,_this.previewBytes);
}



}

/// @nodoc
abstract mixin class $StudioFieldUpdateViewCopyWith<$Res>  {
  factory $StudioFieldUpdateViewCopyWith(StudioFieldUpdateView value, $Res Function(StudioFieldUpdateView) _then) = _$StudioFieldUpdateViewCopyWithImpl;
@useResult
$Res call({
 ThreadContentFieldView field, ThreadFieldChangeView change, int totalBytes, int previewBytes
});


$ThreadContentFieldViewCopyWith<$Res> get field;$ThreadFieldChangeViewCopyWith<$Res> get change;

}
/// @nodoc
class _$StudioFieldUpdateViewCopyWithImpl<$Res>
    implements $StudioFieldUpdateViewCopyWith<$Res> {
  _$StudioFieldUpdateViewCopyWithImpl(this._self, this._then);

  final StudioFieldUpdateView _self;
  final $Res Function(StudioFieldUpdateView) _then;

/// Create a copy of StudioFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field = null,Object? change = null,Object? totalBytes = null,Object? previewBytes = null,}) {
  return _then(StudioFieldUpdateView(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,change: null == change ? _self.change : change // ignore: cast_nullable_to_non_nullable
as ThreadFieldChangeView,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,previewBytes: null == previewBytes ? _self.previewBytes : previewBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of StudioFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}/// Create a copy of StudioFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFieldChangeViewCopyWith<$Res> get change {

  return $ThreadFieldChangeViewCopyWith<$Res>(_self.change, (value) {
    return _then(_self.copyWith(change: value));
  });
}
}


/// Adds pattern-matching-related methods to [StudioFieldUpdateView].
extension StudioFieldUpdateViewPatterns on StudioFieldUpdateView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StudioFieldUpdateView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StudioFieldUpdateView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StudioFieldUpdateView value)  $default,){
final _that = this;
switch (_that) {
case _StudioFieldUpdateView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StudioFieldUpdateView value)?  $default,){
final _that = this;
switch (_that) {
case _StudioFieldUpdateView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadContentFieldView field,  ThreadFieldChangeView change,  int totalBytes,  int previewBytes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StudioFieldUpdateView() when $default != null:
return $default(_that.field,_that.change,_that.totalBytes,_that.previewBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadContentFieldView field,  ThreadFieldChangeView change,  int totalBytes,  int previewBytes)  $default,) {final _that = this;
switch (_that) {
case _StudioFieldUpdateView():
return $default(_that.field,_that.change,_that.totalBytes,_that.previewBytes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadContentFieldView field,  ThreadFieldChangeView change,  int totalBytes,  int previewBytes)?  $default,) {final _that = this;
switch (_that) {
case _StudioFieldUpdateView() when $default != null:
return $default(_that.field,_that.change,_that.totalBytes,_that.previewBytes);case _:
  return null;

}
}

}

/// @nodoc


class _StudioFieldUpdateView extends StudioFieldUpdateView {
  const _StudioFieldUpdateView({required this.field, required this.change, required this.totalBytes, required this.previewBytes}): super._();


@override final  ThreadContentFieldView field;
@override final  ThreadFieldChangeView change;
@override final  int totalBytes;
@override final  int previewBytes;

/// Create a copy of StudioFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioFieldUpdateViewCopyWith<_StudioFieldUpdateView> get copyWith => __$StudioFieldUpdateViewCopyWithImpl<_StudioFieldUpdateView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioFieldUpdateView&&(identical(other.field, field) || other.field == field)&&(identical(other.change, change) || other.change == change)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.previewBytes, previewBytes) || other.previewBytes == previewBytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field,change,totalBytes,previewBytes);
}



}

/// @nodoc
abstract mixin class _$StudioFieldUpdateViewCopyWith<$Res> implements $StudioFieldUpdateViewCopyWith<$Res> {
  factory _$StudioFieldUpdateViewCopyWith(_StudioFieldUpdateView value, $Res Function(_StudioFieldUpdateView) _then) = __$StudioFieldUpdateViewCopyWithImpl;
@override @useResult
$Res call({
 ThreadContentFieldView field, ThreadFieldChangeView change, int totalBytes, int previewBytes
});


@override $ThreadContentFieldViewCopyWith<$Res> get field;@override $ThreadFieldChangeViewCopyWith<$Res> get change;

}
/// @nodoc
class __$StudioFieldUpdateViewCopyWithImpl<$Res>
    implements _$StudioFieldUpdateViewCopyWith<$Res> {
  __$StudioFieldUpdateViewCopyWithImpl(this._self, this._then);

  final _StudioFieldUpdateView _self;
  final $Res Function(_StudioFieldUpdateView) _then;

/// Create a copy of StudioFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field = null,Object? change = null,Object? totalBytes = null,Object? previewBytes = null,}) {
  return _then(_StudioFieldUpdateView(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,change: null == change ? _self.change : change // ignore: cast_nullable_to_non_nullable
as ThreadFieldChangeView,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,previewBytes: null == previewBytes ? _self.previewBytes : previewBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of StudioFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}/// Create a copy of StudioFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFieldChangeViewCopyWith<$Res> get change {

  return $ThreadFieldChangeViewCopyWith<$Res>(_self.change, (value) {
    return _then(_self.copyWith(change: value));
  });
}
}

/// @nodoc
mixin _$StudioTimelineChange {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineChange);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $StudioTimelineChangeCopyWith<$Res>  {
$StudioTimelineChangeCopyWith(StudioTimelineChange _, $Res Function(StudioTimelineChange) __);
}


/// Adds pattern-matching-related methods to [StudioTimelineChange].
extension StudioTimelineChangePatterns on StudioTimelineChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StudioTimelineAdd value)?  add,TResult Function( StudioTimelineUpdateItem value)?  updateItem,TResult Function( StudioTimelineRemove value)?  remove,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StudioTimelineAdd() when add != null:
return add(_that);case StudioTimelineUpdateItem() when updateItem != null:
return updateItem(_that);case StudioTimelineRemove() when remove != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StudioTimelineAdd value)  add,required TResult Function( StudioTimelineUpdateItem value)  updateItem,required TResult Function( StudioTimelineRemove value)  remove,}){
final _that = this;
switch (_that) {
case StudioTimelineAdd():
return add(_that);case StudioTimelineUpdateItem():
return updateItem(_that);case StudioTimelineRemove():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StudioTimelineAdd value)?  add,TResult? Function( StudioTimelineUpdateItem value)?  updateItem,TResult? Function( StudioTimelineRemove value)?  remove,}){
final _that = this;
switch (_that) {
case StudioTimelineAdd() when add != null:
return add(_that);case StudioTimelineUpdateItem() when updateItem != null:
return updateItem(_that);case StudioTimelineRemove() when remove != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( StudioTimelineItem item)?  add,TResult Function( String itemId,  int expectedRevision,  int revision,  int omittedBytes,  bool saved,  StudioTimelineLifecycle lifecycle,  ThreadItemView? itemShell,  List<StudioFieldUpdateView> fields)?  updateItem,TResult Function( String itemId)?  remove,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StudioTimelineAdd() when add != null:
return add(_that.item);case StudioTimelineUpdateItem() when updateItem != null:
return updateItem(_that.itemId,_that.expectedRevision,_that.revision,_that.omittedBytes,_that.saved,_that.lifecycle,_that.itemShell,_that.fields);case StudioTimelineRemove() when remove != null:
return remove(_that.itemId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( StudioTimelineItem item)  add,required TResult Function( String itemId,  int expectedRevision,  int revision,  int omittedBytes,  bool saved,  StudioTimelineLifecycle lifecycle,  ThreadItemView? itemShell,  List<StudioFieldUpdateView> fields)  updateItem,required TResult Function( String itemId)  remove,}) {final _that = this;
switch (_that) {
case StudioTimelineAdd():
return add(_that.item);case StudioTimelineUpdateItem():
return updateItem(_that.itemId,_that.expectedRevision,_that.revision,_that.omittedBytes,_that.saved,_that.lifecycle,_that.itemShell,_that.fields);case StudioTimelineRemove():
return remove(_that.itemId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( StudioTimelineItem item)?  add,TResult? Function( String itemId,  int expectedRevision,  int revision,  int omittedBytes,  bool saved,  StudioTimelineLifecycle lifecycle,  ThreadItemView? itemShell,  List<StudioFieldUpdateView> fields)?  updateItem,TResult? Function( String itemId)?  remove,}) {final _that = this;
switch (_that) {
case StudioTimelineAdd() when add != null:
return add(_that.item);case StudioTimelineUpdateItem() when updateItem != null:
return updateItem(_that.itemId,_that.expectedRevision,_that.revision,_that.omittedBytes,_that.saved,_that.lifecycle,_that.itemShell,_that.fields);case StudioTimelineRemove() when remove != null:
return remove(_that.itemId);case _:
  return null;

}
}

}

/// @nodoc


class StudioTimelineAdd extends StudioTimelineChange {
  const StudioTimelineAdd(this.item): super._();


 final  StudioTimelineItem item;

/// Create a copy of StudioTimelineChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineAddCopyWith<StudioTimelineAdd> get copyWith => _$StudioTimelineAddCopyWithImpl<StudioTimelineAdd>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineAdd&&(identical(other.item, item) || other.item == item));
}


@override
int get hashCode {
    return Object.hash(runtimeType,item);
}



}

/// @nodoc
abstract mixin class $StudioTimelineAddCopyWith<$Res> implements $StudioTimelineChangeCopyWith<$Res> {
  factory $StudioTimelineAddCopyWith(StudioTimelineAdd value, $Res Function(StudioTimelineAdd) _then) = _$StudioTimelineAddCopyWithImpl;
@useResult
$Res call({
 StudioTimelineItem item
});


$StudioTimelineItemCopyWith<$Res> get item;

}
/// @nodoc
class _$StudioTimelineAddCopyWithImpl<$Res>
    implements $StudioTimelineAddCopyWith<$Res> {
  _$StudioTimelineAddCopyWithImpl(this._self, this._then);

  final StudioTimelineAdd _self;
  final $Res Function(StudioTimelineAdd) _then;

/// Create a copy of StudioTimelineChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? item = null,}) {
  return _then(StudioTimelineAdd(
null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as StudioTimelineItem,
  ));
}

/// Create a copy of StudioTimelineChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelineItemCopyWith<$Res> get item {

  return $StudioTimelineItemCopyWith<$Res>(_self.item, (value) {
    return _then(_self.copyWith(item: value));
  });
}
}


/// @nodoc


class StudioTimelineRemove extends StudioTimelineChange {
  const StudioTimelineRemove(this.itemId): super._();


 final  String itemId;

/// Create a copy of StudioTimelineChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineRemoveCopyWith<StudioTimelineRemove> get copyWith => _$StudioTimelineRemoveCopyWithImpl<StudioTimelineRemove>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineRemove&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId);
}



}

/// @nodoc
abstract mixin class $StudioTimelineRemoveCopyWith<$Res> implements $StudioTimelineChangeCopyWith<$Res> {
  factory $StudioTimelineRemoveCopyWith(StudioTimelineRemove value, $Res Function(StudioTimelineRemove) _then) = _$StudioTimelineRemoveCopyWithImpl;
@useResult
$Res call({
 String itemId
});




}
/// @nodoc
class _$StudioTimelineRemoveCopyWithImpl<$Res>
    implements $StudioTimelineRemoveCopyWith<$Res> {
  _$StudioTimelineRemoveCopyWithImpl(this._self, this._then);

  final StudioTimelineRemove _self;
  final $Res Function(StudioTimelineRemove) _then;

/// Create a copy of StudioTimelineChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,}) {
  return _then(StudioTimelineRemove(
null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$StudioTimelineUpdateItem {


/// Create a copy of StudioTimelineUpdateItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineUpdateItemCopyWith<StudioTimelineUpdateItem> get copyWith => _$StudioTimelineUpdateItemCopyWithImpl<StudioTimelineUpdateItem>(this as StudioTimelineUpdateItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioTimelineUpdateItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineUpdateItem&&(identical(other.itemId, _this.itemId) || other.itemId == _this.itemId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.omittedBytes, _this.omittedBytes) || other.omittedBytes == _this.omittedBytes)&&(identical(other.saved, _this.saved) || other.saved == _this.saved)&&(identical(other.lifecycle, _this.lifecycle) || other.lifecycle == _this.lifecycle)&&(identical(other.itemShell, _this.itemShell) || other.itemShell == _this.itemShell)&&const DeepCollectionEquality().equals(other.fields, _this.fields));
}


@override
int get hashCode {
  final _this = this as StudioTimelineUpdateItem;
  return Object.hash(runtimeType,_this.itemId,_this.expectedRevision,_this.revision,_this.omittedBytes,_this.saved,_this.lifecycle,_this.itemShell,const DeepCollectionEquality().hash(_this.fields));
}



}

/// @nodoc
abstract mixin class $StudioTimelineUpdateItemCopyWith<$Res> implements $StudioTimelineChangeCopyWith<$Res> {
  factory $StudioTimelineUpdateItemCopyWith(StudioTimelineUpdateItem value, $Res Function(StudioTimelineUpdateItem) _then) = _$StudioTimelineUpdateItemCopyWithImpl;
@useResult
$Res call({
 String itemId, int expectedRevision, int revision, int omittedBytes, bool saved, StudioTimelineLifecycle lifecycle, ThreadItemView? itemShell, List<StudioFieldUpdateView> fields
});


$ThreadItemViewCopyWith<$Res>? get itemShell;

}
/// @nodoc
class _$StudioTimelineUpdateItemCopyWithImpl<$Res>
    implements $StudioTimelineUpdateItemCopyWith<$Res> {
  _$StudioTimelineUpdateItemCopyWithImpl(this._self, this._then);

  final StudioTimelineUpdateItem _self;
  final $Res Function(StudioTimelineUpdateItem) _then;

/// Create a copy of StudioTimelineUpdateItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? itemId = null,Object? expectedRevision = null,Object? revision = null,Object? omittedBytes = null,Object? saved = null,Object? lifecycle = null,Object? itemShell = freezed,Object? fields = null,}) {
  return _then(StudioTimelineUpdateItem(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,omittedBytes: null == omittedBytes ? _self.omittedBytes : omittedBytes // ignore: cast_nullable_to_non_nullable
as int,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as StudioTimelineLifecycle,itemShell: freezed == itemShell ? _self.itemShell : itemShell // ignore: cast_nullable_to_non_nullable
as ThreadItemView?,fields: null == fields ? _self.fields : fields // ignore: cast_nullable_to_non_nullable
as List<StudioFieldUpdateView>,
  ));
}
/// Create a copy of StudioTimelineUpdateItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadItemViewCopyWith<$Res>? get itemShell {
    if (_self.itemShell == null) {
    return null;
  }

  return $ThreadItemViewCopyWith<$Res>(_self.itemShell!, (value) {
    return _then(_self.copyWith(itemShell: value));
  });
}
}


/// Adds pattern-matching-related methods to [StudioTimelineUpdateItem].
extension StudioTimelineUpdateItemPatterns on StudioTimelineUpdateItem {
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
mixin _$StudioTimelineUpdate {

 String get subscriptionId;
/// Create a copy of StudioTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineUpdateCopyWith<StudioTimelineUpdate> get copyWith => _$StudioTimelineUpdateCopyWithImpl<StudioTimelineUpdate>(this as StudioTimelineUpdate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioTimelineUpdate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineUpdate&&(identical(other.subscriptionId, _this.subscriptionId) || other.subscriptionId == _this.subscriptionId));
}


@override
int get hashCode {
  final _this = this as StudioTimelineUpdate;
  return Object.hash(runtimeType,_this.subscriptionId);
}



}

/// @nodoc
abstract mixin class $StudioTimelineUpdateCopyWith<$Res>  {
  factory $StudioTimelineUpdateCopyWith(StudioTimelineUpdate value, $Res Function(StudioTimelineUpdate) _then) = _$StudioTimelineUpdateCopyWithImpl;
@useResult
$Res call({
 String subscriptionId
});




}
/// @nodoc
class _$StudioTimelineUpdateCopyWithImpl<$Res>
    implements $StudioTimelineUpdateCopyWith<$Res> {
  _$StudioTimelineUpdateCopyWithImpl(this._self, this._then);

  final StudioTimelineUpdate _self;
  final $Res Function(StudioTimelineUpdate) _then;

/// Create a copy of StudioTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? subscriptionId = null,}) {
  return _then(_self.copyWith(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [StudioTimelineUpdate].
extension StudioTimelineUpdatePatterns on StudioTimelineUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StudioTimelinePatch value)?  patch,TResult Function( StudioTimelineResync value)?  resync,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StudioTimelinePatch() when patch != null:
return patch(_that);case StudioTimelineResync() when resync != null:
return resync(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StudioTimelinePatch value)  patch,required TResult Function( StudioTimelineResync value)  resync,}){
final _that = this;
switch (_that) {
case StudioTimelinePatch():
return patch(_that);case StudioTimelineResync():
return resync(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StudioTimelinePatch value)?  patch,TResult? Function( StudioTimelineResync value)?  resync,}){
final _that = this;
switch (_that) {
case StudioTimelinePatch() when patch != null:
return patch(_that);case StudioTimelineResync() when resync != null:
return resync(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String subscriptionId,  int from,  int to,  List<StudioTimelineChange> changes,  StudioTimelinePriority priority)?  patch,TResult Function( String subscriptionId,  StudioTimelineResyncReason reason,  StudioTimelineBaseline baseline)?  resync,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StudioTimelinePatch() when patch != null:
return patch(_that.subscriptionId,_that.from,_that.to,_that.changes,_that.priority);case StudioTimelineResync() when resync != null:
return resync(_that.subscriptionId,_that.reason,_that.baseline);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String subscriptionId,  int from,  int to,  List<StudioTimelineChange> changes,  StudioTimelinePriority priority)  patch,required TResult Function( String subscriptionId,  StudioTimelineResyncReason reason,  StudioTimelineBaseline baseline)  resync,}) {final _that = this;
switch (_that) {
case StudioTimelinePatch():
return patch(_that.subscriptionId,_that.from,_that.to,_that.changes,_that.priority);case StudioTimelineResync():
return resync(_that.subscriptionId,_that.reason,_that.baseline);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String subscriptionId,  int from,  int to,  List<StudioTimelineChange> changes,  StudioTimelinePriority priority)?  patch,TResult? Function( String subscriptionId,  StudioTimelineResyncReason reason,  StudioTimelineBaseline baseline)?  resync,}) {final _that = this;
switch (_that) {
case StudioTimelinePatch() when patch != null:
return patch(_that.subscriptionId,_that.from,_that.to,_that.changes,_that.priority);case StudioTimelineResync() when resync != null:
return resync(_that.subscriptionId,_that.reason,_that.baseline);case _:
  return null;

}
}

}


/// @nodoc


class StudioTimelineResync extends StudioTimelineUpdate {
  const StudioTimelineResync({required this.subscriptionId, required this.reason, required this.baseline}): super._();


@override final  String subscriptionId;
 final  StudioTimelineResyncReason reason;
 final  StudioTimelineBaseline baseline;

/// Create a copy of StudioTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineResyncCopyWith<StudioTimelineResync> get copyWith => _$StudioTimelineResyncCopyWithImpl<StudioTimelineResync>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineResync&&(identical(other.subscriptionId, subscriptionId) || other.subscriptionId == subscriptionId)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.baseline, baseline) || other.baseline == baseline));
}


@override
int get hashCode {
    return Object.hash(runtimeType,subscriptionId,reason,baseline);
}



}

/// @nodoc
abstract mixin class $StudioTimelineResyncCopyWith<$Res> implements $StudioTimelineUpdateCopyWith<$Res> {
  factory $StudioTimelineResyncCopyWith(StudioTimelineResync value, $Res Function(StudioTimelineResync) _then) = _$StudioTimelineResyncCopyWithImpl;
@override @useResult
$Res call({
 String subscriptionId, StudioTimelineResyncReason reason, StudioTimelineBaseline baseline
});


$StudioTimelineBaselineCopyWith<$Res> get baseline;

}
/// @nodoc
class _$StudioTimelineResyncCopyWithImpl<$Res>
    implements $StudioTimelineResyncCopyWith<$Res> {
  _$StudioTimelineResyncCopyWithImpl(this._self, this._then);

  final StudioTimelineResync _self;
  final $Res Function(StudioTimelineResync) _then;

/// Create a copy of StudioTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? subscriptionId = null,Object? reason = null,Object? baseline = null,}) {
  return _then(StudioTimelineResync(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as StudioTimelineResyncReason,baseline: null == baseline ? _self.baseline : baseline // ignore: cast_nullable_to_non_nullable
as StudioTimelineBaseline,
  ));
}

/// Create a copy of StudioTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelineBaselineCopyWith<$Res> get baseline {

  return $StudioTimelineBaselineCopyWith<$Res>(_self.baseline, (value) {
    return _then(_self.copyWith(baseline: value));
  });
}
}

/// @nodoc
mixin _$StudioTimelinePatch {


/// Create a copy of StudioTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelinePatchCopyWith<StudioTimelinePatch> get copyWith => _$StudioTimelinePatchCopyWithImpl<StudioTimelinePatch>(this as StudioTimelinePatch, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioTimelinePatch;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelinePatch&&(identical(other.subscriptionId, _this.subscriptionId) || other.subscriptionId == _this.subscriptionId)&&(identical(other.from, _this.from) || other.from == _this.from)&&(identical(other.to, _this.to) || other.to == _this.to)&&const DeepCollectionEquality().equals(other.changes, _this.changes)&&(identical(other.priority, _this.priority) || other.priority == _this.priority));
}


@override
int get hashCode {
  final _this = this as StudioTimelinePatch;
  return Object.hash(runtimeType,_this.subscriptionId,_this.from,_this.to,const DeepCollectionEquality().hash(_this.changes),_this.priority);
}



}

/// @nodoc
abstract mixin class $StudioTimelinePatchCopyWith<$Res> implements $StudioTimelineUpdateCopyWith<$Res> {
  factory $StudioTimelinePatchCopyWith(StudioTimelinePatch value, $Res Function(StudioTimelinePatch) _then) = _$StudioTimelinePatchCopyWithImpl;
@useResult
$Res call({
 String subscriptionId, int from, int to, List<StudioTimelineChange> changes, StudioTimelinePriority priority
});




}
/// @nodoc
class _$StudioTimelinePatchCopyWithImpl<$Res>
    implements $StudioTimelinePatchCopyWith<$Res> {
  _$StudioTimelinePatchCopyWithImpl(this._self, this._then);

  final StudioTimelinePatch _self;
  final $Res Function(StudioTimelinePatch) _then;

/// Create a copy of StudioTimelinePatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? subscriptionId = null,Object? from = null,Object? to = null,Object? changes = null,Object? priority = null,}) {
  return _then(StudioTimelinePatch(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as int,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as int,changes: null == changes ? _self.changes : changes // ignore: cast_nullable_to_non_nullable
as List<StudioTimelineChange>,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as StudioTimelinePriority,
  ));
}

}


/// Adds pattern-matching-related methods to [StudioTimelinePatch].
extension StudioTimelinePatchPatterns on StudioTimelinePatch {
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
mixin _$StudioTimelineFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $StudioTimelineFrameCopyWith<$Res>  {
$StudioTimelineFrameCopyWith(StudioTimelineFrame _, $Res Function(StudioTimelineFrame) __);
}


/// Adds pattern-matching-related methods to [StudioTimelineFrame].
extension StudioTimelineFramePatterns on StudioTimelineFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StudioTimelineBaselineFrame value)?  baseline,TResult Function( StudioTimelinePatchFrame value)?  patch,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StudioTimelineBaselineFrame() when baseline != null:
return baseline(_that);case StudioTimelinePatchFrame() when patch != null:
return patch(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StudioTimelineBaselineFrame value)  baseline,required TResult Function( StudioTimelinePatchFrame value)  patch,}){
final _that = this;
switch (_that) {
case StudioTimelineBaselineFrame():
return baseline(_that);case StudioTimelinePatchFrame():
return patch(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StudioTimelineBaselineFrame value)?  baseline,TResult? Function( StudioTimelinePatchFrame value)?  patch,}){
final _that = this;
switch (_that) {
case StudioTimelineBaselineFrame() when baseline != null:
return baseline(_that);case StudioTimelinePatchFrame() when patch != null:
return patch(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( StudioTimelineBaseline baseline,  StudioTimelineResyncReason? resyncReason)?  baseline,TResult Function( StudioTimelinePatch patch)?  patch,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StudioTimelineBaselineFrame() when baseline != null:
return baseline(_that.baseline,_that.resyncReason);case StudioTimelinePatchFrame() when patch != null:
return patch(_that.patch);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( StudioTimelineBaseline baseline,  StudioTimelineResyncReason? resyncReason)  baseline,required TResult Function( StudioTimelinePatch patch)  patch,}) {final _that = this;
switch (_that) {
case StudioTimelineBaselineFrame():
return baseline(_that.baseline,_that.resyncReason);case StudioTimelinePatchFrame():
return patch(_that.patch);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( StudioTimelineBaseline baseline,  StudioTimelineResyncReason? resyncReason)?  baseline,TResult? Function( StudioTimelinePatch patch)?  patch,}) {final _that = this;
switch (_that) {
case StudioTimelineBaselineFrame() when baseline != null:
return baseline(_that.baseline,_that.resyncReason);case StudioTimelinePatchFrame() when patch != null:
return patch(_that.patch);case _:
  return null;

}
}

}

/// @nodoc


class StudioTimelineBaselineFrame extends StudioTimelineFrame {
  const StudioTimelineBaselineFrame(this.baseline, {this.resyncReason}): super._();


 final  StudioTimelineBaseline baseline;
 final  StudioTimelineResyncReason? resyncReason;

/// Create a copy of StudioTimelineFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineBaselineFrameCopyWith<StudioTimelineBaselineFrame> get copyWith => _$StudioTimelineBaselineFrameCopyWithImpl<StudioTimelineBaselineFrame>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineBaselineFrame&&(identical(other.baseline, baseline) || other.baseline == baseline)&&(identical(other.resyncReason, resyncReason) || other.resyncReason == resyncReason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,baseline,resyncReason);
}



}

/// @nodoc
abstract mixin class $StudioTimelineBaselineFrameCopyWith<$Res> implements $StudioTimelineFrameCopyWith<$Res> {
  factory $StudioTimelineBaselineFrameCopyWith(StudioTimelineBaselineFrame value, $Res Function(StudioTimelineBaselineFrame) _then) = _$StudioTimelineBaselineFrameCopyWithImpl;
@useResult
$Res call({
 StudioTimelineBaseline baseline, StudioTimelineResyncReason? resyncReason
});


$StudioTimelineBaselineCopyWith<$Res> get baseline;

}
/// @nodoc
class _$StudioTimelineBaselineFrameCopyWithImpl<$Res>
    implements $StudioTimelineBaselineFrameCopyWith<$Res> {
  _$StudioTimelineBaselineFrameCopyWithImpl(this._self, this._then);

  final StudioTimelineBaselineFrame _self;
  final $Res Function(StudioTimelineBaselineFrame) _then;

/// Create a copy of StudioTimelineFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? baseline = null,Object? resyncReason = freezed,}) {
  return _then(StudioTimelineBaselineFrame(
null == baseline ? _self.baseline : baseline // ignore: cast_nullable_to_non_nullable
as StudioTimelineBaseline,resyncReason: freezed == resyncReason ? _self.resyncReason : resyncReason // ignore: cast_nullable_to_non_nullable
as StudioTimelineResyncReason?,
  ));
}

/// Create a copy of StudioTimelineFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelineBaselineCopyWith<$Res> get baseline {

  return $StudioTimelineBaselineCopyWith<$Res>(_self.baseline, (value) {
    return _then(_self.copyWith(baseline: value));
  });
}
}

/// @nodoc


class StudioTimelinePatchFrame extends StudioTimelineFrame {
  const StudioTimelinePatchFrame(this.patch): super._();


 final  StudioTimelinePatch patch;

/// Create a copy of StudioTimelineFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelinePatchFrameCopyWith<StudioTimelinePatchFrame> get copyWith => _$StudioTimelinePatchFrameCopyWithImpl<StudioTimelinePatchFrame>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelinePatchFrame&&(identical(other.patch, patch) || other.patch == patch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,patch);
}



}

/// @nodoc
abstract mixin class $StudioTimelinePatchFrameCopyWith<$Res> implements $StudioTimelineFrameCopyWith<$Res> {
  factory $StudioTimelinePatchFrameCopyWith(StudioTimelinePatchFrame value, $Res Function(StudioTimelinePatchFrame) _then) = _$StudioTimelinePatchFrameCopyWithImpl;
@useResult
$Res call({
 StudioTimelinePatch patch
});


$StudioTimelinePatchCopyWith<$Res> get patch;

}
/// @nodoc
class _$StudioTimelinePatchFrameCopyWithImpl<$Res>
    implements $StudioTimelinePatchFrameCopyWith<$Res> {
  _$StudioTimelinePatchFrameCopyWithImpl(this._self, this._then);

  final StudioTimelinePatchFrame _self;
  final $Res Function(StudioTimelinePatchFrame) _then;

/// Create a copy of StudioTimelineFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? patch = null,}) {
  return _then(StudioTimelinePatchFrame(
null == patch ? _self.patch : patch // ignore: cast_nullable_to_non_nullable
as StudioTimelinePatch,
  ));
}

/// Create a copy of StudioTimelineFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelinePatchCopyWith<$Res> get patch {

  return $StudioTimelinePatchCopyWith<$Res>(_self.patch, (value) {
    return _then(_self.copyWith(patch: value));
  });
}
}

/// @nodoc
mixin _$StudioTimelineDetailQuery {

 ThreadContentFieldView get field; int get revision; String? get continuation; int? get maxBytes;
/// Create a copy of StudioTimelineDetailQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineDetailQueryCopyWith<StudioTimelineDetailQuery> get copyWith => _$StudioTimelineDetailQueryCopyWithImpl<StudioTimelineDetailQuery>(this as StudioTimelineDetailQuery, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioTimelineDetailQuery;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineDetailQuery&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.continuation, _this.continuation) || other.continuation == _this.continuation)&&(identical(other.maxBytes, _this.maxBytes) || other.maxBytes == _this.maxBytes));
}


@override
int get hashCode {
  final _this = this as StudioTimelineDetailQuery;
  return Object.hash(runtimeType,_this.field,_this.revision,_this.continuation,_this.maxBytes);
}



}

/// @nodoc
abstract mixin class $StudioTimelineDetailQueryCopyWith<$Res>  {
  factory $StudioTimelineDetailQueryCopyWith(StudioTimelineDetailQuery value, $Res Function(StudioTimelineDetailQuery) _then) = _$StudioTimelineDetailQueryCopyWithImpl;
@useResult
$Res call({
 ThreadContentFieldView field, int revision, String? continuation, int? maxBytes
});


$ThreadContentFieldViewCopyWith<$Res> get field;

}
/// @nodoc
class _$StudioTimelineDetailQueryCopyWithImpl<$Res>
    implements $StudioTimelineDetailQueryCopyWith<$Res> {
  _$StudioTimelineDetailQueryCopyWithImpl(this._self, this._then);

  final StudioTimelineDetailQuery _self;
  final $Res Function(StudioTimelineDetailQuery) _then;

/// Create a copy of StudioTimelineDetailQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field = null,Object? revision = null,Object? continuation = freezed,Object? maxBytes = freezed,}) {
  return _then(StudioTimelineDetailQuery(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as String?,maxBytes: freezed == maxBytes ? _self.maxBytes : maxBytes // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of StudioTimelineDetailQuery
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}
}


/// Adds pattern-matching-related methods to [StudioTimelineDetailQuery].
extension StudioTimelineDetailQueryPatterns on StudioTimelineDetailQuery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StudioTimelineDetailQuery value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StudioTimelineDetailQuery() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StudioTimelineDetailQuery value)  $default,){
final _that = this;
switch (_that) {
case _StudioTimelineDetailQuery():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StudioTimelineDetailQuery value)?  $default,){
final _that = this;
switch (_that) {
case _StudioTimelineDetailQuery() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadContentFieldView field,  int revision,  String? continuation,  int? maxBytes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StudioTimelineDetailQuery() when $default != null:
return $default(_that.field,_that.revision,_that.continuation,_that.maxBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadContentFieldView field,  int revision,  String? continuation,  int? maxBytes)  $default,) {final _that = this;
switch (_that) {
case _StudioTimelineDetailQuery():
return $default(_that.field,_that.revision,_that.continuation,_that.maxBytes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadContentFieldView field,  int revision,  String? continuation,  int? maxBytes)?  $default,) {final _that = this;
switch (_that) {
case _StudioTimelineDetailQuery() when $default != null:
return $default(_that.field,_that.revision,_that.continuation,_that.maxBytes);case _:
  return null;

}
}

}

/// @nodoc


class _StudioTimelineDetailQuery extends StudioTimelineDetailQuery {
  const _StudioTimelineDetailQuery({required this.field, required this.revision, this.continuation, this.maxBytes}): super._();


@override final  ThreadContentFieldView field;
@override final  int revision;
@override final  String? continuation;
@override final  int? maxBytes;

/// Create a copy of StudioTimelineDetailQuery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioTimelineDetailQueryCopyWith<_StudioTimelineDetailQuery> get copyWith => __$StudioTimelineDetailQueryCopyWithImpl<_StudioTimelineDetailQuery>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioTimelineDetailQuery&&(identical(other.field, field) || other.field == field)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.continuation, continuation) || other.continuation == continuation)&&(identical(other.maxBytes, maxBytes) || other.maxBytes == maxBytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field,revision,continuation,maxBytes);
}



}

/// @nodoc
abstract mixin class _$StudioTimelineDetailQueryCopyWith<$Res> implements $StudioTimelineDetailQueryCopyWith<$Res> {
  factory _$StudioTimelineDetailQueryCopyWith(_StudioTimelineDetailQuery value, $Res Function(_StudioTimelineDetailQuery) _then) = __$StudioTimelineDetailQueryCopyWithImpl;
@override @useResult
$Res call({
 ThreadContentFieldView field, int revision, String? continuation, int? maxBytes
});


@override $ThreadContentFieldViewCopyWith<$Res> get field;

}
/// @nodoc
class __$StudioTimelineDetailQueryCopyWithImpl<$Res>
    implements _$StudioTimelineDetailQueryCopyWith<$Res> {
  __$StudioTimelineDetailQueryCopyWithImpl(this._self, this._then);

  final _StudioTimelineDetailQuery _self;
  final $Res Function(_StudioTimelineDetailQuery) _then;

/// Create a copy of StudioTimelineDetailQuery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field = null,Object? revision = null,Object? continuation = freezed,Object? maxBytes = freezed,}) {
  return _then(_StudioTimelineDetailQuery(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as String?,maxBytes: freezed == maxBytes ? _self.maxBytes : maxBytes // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of StudioTimelineDetailQuery
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}
}

/// @nodoc
mixin _$StudioTimelineDetailChunk {

 String get itemId; ThreadContentFieldView get field; int get revision; String get text; int get totalBytes; String? get continuation;
/// Create a copy of StudioTimelineDetailChunk
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineDetailChunkCopyWith<StudioTimelineDetailChunk> get copyWith => _$StudioTimelineDetailChunkCopyWithImpl<StudioTimelineDetailChunk>(this as StudioTimelineDetailChunk, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioTimelineDetailChunk;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineDetailChunk&&(identical(other.itemId, _this.itemId) || other.itemId == _this.itemId)&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.totalBytes, _this.totalBytes) || other.totalBytes == _this.totalBytes)&&(identical(other.continuation, _this.continuation) || other.continuation == _this.continuation));
}


@override
int get hashCode {
  final _this = this as StudioTimelineDetailChunk;
  return Object.hash(runtimeType,_this.itemId,_this.field,_this.revision,_this.text,_this.totalBytes,_this.continuation);
}



}

/// @nodoc
abstract mixin class $StudioTimelineDetailChunkCopyWith<$Res>  {
  factory $StudioTimelineDetailChunkCopyWith(StudioTimelineDetailChunk value, $Res Function(StudioTimelineDetailChunk) _then) = _$StudioTimelineDetailChunkCopyWithImpl;
@useResult
$Res call({
 String itemId, ThreadContentFieldView field, int revision, String text, int totalBytes, String? continuation
});


$ThreadContentFieldViewCopyWith<$Res> get field;

}
/// @nodoc
class _$StudioTimelineDetailChunkCopyWithImpl<$Res>
    implements $StudioTimelineDetailChunkCopyWith<$Res> {
  _$StudioTimelineDetailChunkCopyWithImpl(this._self, this._then);

  final StudioTimelineDetailChunk _self;
  final $Res Function(StudioTimelineDetailChunk) _then;

/// Create a copy of StudioTimelineDetailChunk
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? itemId = null,Object? field = null,Object? revision = null,Object? text = null,Object? totalBytes = null,Object? continuation = freezed,}) {
  return _then(StudioTimelineDetailChunk(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of StudioTimelineDetailChunk
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}
}


/// Adds pattern-matching-related methods to [StudioTimelineDetailChunk].
extension StudioTimelineDetailChunkPatterns on StudioTimelineDetailChunk {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StudioTimelineDetailChunk value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StudioTimelineDetailChunk() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StudioTimelineDetailChunk value)  $default,){
final _that = this;
switch (_that) {
case _StudioTimelineDetailChunk():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StudioTimelineDetailChunk value)?  $default,){
final _that = this;
switch (_that) {
case _StudioTimelineDetailChunk() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String itemId,  ThreadContentFieldView field,  int revision,  String text,  int totalBytes,  String? continuation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StudioTimelineDetailChunk() when $default != null:
return $default(_that.itemId,_that.field,_that.revision,_that.text,_that.totalBytes,_that.continuation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String itemId,  ThreadContentFieldView field,  int revision,  String text,  int totalBytes,  String? continuation)  $default,) {final _that = this;
switch (_that) {
case _StudioTimelineDetailChunk():
return $default(_that.itemId,_that.field,_that.revision,_that.text,_that.totalBytes,_that.continuation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String itemId,  ThreadContentFieldView field,  int revision,  String text,  int totalBytes,  String? continuation)?  $default,) {final _that = this;
switch (_that) {
case _StudioTimelineDetailChunk() when $default != null:
return $default(_that.itemId,_that.field,_that.revision,_that.text,_that.totalBytes,_that.continuation);case _:
  return null;

}
}

}

/// @nodoc


class _StudioTimelineDetailChunk extends StudioTimelineDetailChunk {
  const _StudioTimelineDetailChunk({required this.itemId, required this.field, required this.revision, required this.text, required this.totalBytes, this.continuation}): super._();


@override final  String itemId;
@override final  ThreadContentFieldView field;
@override final  int revision;
@override final  String text;
@override final  int totalBytes;
@override final  String? continuation;

/// Create a copy of StudioTimelineDetailChunk
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioTimelineDetailChunkCopyWith<_StudioTimelineDetailChunk> get copyWith => __$StudioTimelineDetailChunkCopyWithImpl<_StudioTimelineDetailChunk>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioTimelineDetailChunk&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.field, field) || other.field == field)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.text, text) || other.text == text)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.continuation, continuation) || other.continuation == continuation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId,field,revision,text,totalBytes,continuation);
}



}

/// @nodoc
abstract mixin class _$StudioTimelineDetailChunkCopyWith<$Res> implements $StudioTimelineDetailChunkCopyWith<$Res> {
  factory _$StudioTimelineDetailChunkCopyWith(_StudioTimelineDetailChunk value, $Res Function(_StudioTimelineDetailChunk) _then) = __$StudioTimelineDetailChunkCopyWithImpl;
@override @useResult
$Res call({
 String itemId, ThreadContentFieldView field, int revision, String text, int totalBytes, String? continuation
});


@override $ThreadContentFieldViewCopyWith<$Res> get field;

}
/// @nodoc
class __$StudioTimelineDetailChunkCopyWithImpl<$Res>
    implements _$StudioTimelineDetailChunkCopyWith<$Res> {
  __$StudioTimelineDetailChunkCopyWithImpl(this._self, this._then);

  final _StudioTimelineDetailChunk _self;
  final $Res Function(_StudioTimelineDetailChunk) _then;

/// Create a copy of StudioTimelineDetailChunk
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? itemId = null,Object? field = null,Object? revision = null,Object? text = null,Object? totalBytes = null,Object? continuation = freezed,}) {
  return _then(_StudioTimelineDetailChunk(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of StudioTimelineDetailChunk
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}
}

/// @nodoc
mixin _$StudioTimelineFeedFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineFeedFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $StudioTimelineFeedFrameCopyWith<$Res>  {
$StudioTimelineFeedFrameCopyWith(StudioTimelineFeedFrame _, $Res Function(StudioTimelineFeedFrame) __);
}


/// Adds pattern-matching-related methods to [StudioTimelineFeedFrame].
extension StudioTimelineFeedFramePatterns on StudioTimelineFeedFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StudioTimelineFeedData value)?  data,TResult Function( StudioTimelineFeedFailure value)?  failure,TResult Function( StudioTimelineFeedClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StudioTimelineFeedData() when data != null:
return data(_that);case StudioTimelineFeedFailure() when failure != null:
return failure(_that);case StudioTimelineFeedClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StudioTimelineFeedData value)  data,required TResult Function( StudioTimelineFeedFailure value)  failure,required TResult Function( StudioTimelineFeedClosed value)  closed,}){
final _that = this;
switch (_that) {
case StudioTimelineFeedData():
return data(_that);case StudioTimelineFeedFailure():
return failure(_that);case StudioTimelineFeedClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StudioTimelineFeedData value)?  data,TResult? Function( StudioTimelineFeedFailure value)?  failure,TResult? Function( StudioTimelineFeedClosed value)?  closed,}){
final _that = this;
switch (_that) {
case StudioTimelineFeedData() when data != null:
return data(_that);case StudioTimelineFeedFailure() when failure != null:
return failure(_that);case StudioTimelineFeedClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  StudioTimelineFeedEvent event)?  data,TResult Function( StudioFailure error)?  failure,TResult Function()?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StudioTimelineFeedData() when data != null:
return data(_that.deliverySequence,_that.event);case StudioTimelineFeedFailure() when failure != null:
return failure(_that.error);case StudioTimelineFeedClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  StudioTimelineFeedEvent event)  data,required TResult Function( StudioFailure error)  failure,required TResult Function()  closed,}) {final _that = this;
switch (_that) {
case StudioTimelineFeedData():
return data(_that.deliverySequence,_that.event);case StudioTimelineFeedFailure():
return failure(_that.error);case StudioTimelineFeedClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  StudioTimelineFeedEvent event)?  data,TResult? Function( StudioFailure error)?  failure,TResult? Function()?  closed,}) {final _that = this;
switch (_that) {
case StudioTimelineFeedData() when data != null:
return data(_that.deliverySequence,_that.event);case StudioTimelineFeedFailure() when failure != null:
return failure(_that.error);case StudioTimelineFeedClosed() when closed != null:
return closed();case _:
  return null;

}
}

}

/// @nodoc


class StudioTimelineFeedData extends StudioTimelineFeedFrame {
  const StudioTimelineFeedData({required this.deliverySequence, required this.event}): super._();


 final  int deliverySequence;
 final  StudioTimelineFeedEvent event;

/// Create a copy of StudioTimelineFeedFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineFeedDataCopyWith<StudioTimelineFeedData> get copyWith => _$StudioTimelineFeedDataCopyWithImpl<StudioTimelineFeedData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineFeedData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $StudioTimelineFeedDataCopyWith<$Res> implements $StudioTimelineFeedFrameCopyWith<$Res> {
  factory $StudioTimelineFeedDataCopyWith(StudioTimelineFeedData value, $Res Function(StudioTimelineFeedData) _then) = _$StudioTimelineFeedDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, StudioTimelineFeedEvent event
});


$StudioTimelineFeedEventCopyWith<$Res> get event;

}
/// @nodoc
class _$StudioTimelineFeedDataCopyWithImpl<$Res>
    implements $StudioTimelineFeedDataCopyWith<$Res> {
  _$StudioTimelineFeedDataCopyWithImpl(this._self, this._then);

  final StudioTimelineFeedData _self;
  final $Res Function(StudioTimelineFeedData) _then;

/// Create a copy of StudioTimelineFeedFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(StudioTimelineFeedData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as StudioTimelineFeedEvent,
  ));
}

/// Create a copy of StudioTimelineFeedFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelineFeedEventCopyWith<$Res> get event {

  return $StudioTimelineFeedEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class StudioTimelineFeedFailure extends StudioTimelineFeedFrame {
  const StudioTimelineFeedFailure({required this.error}): super._();


 final  StudioFailure error;

/// Create a copy of StudioTimelineFeedFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineFeedFailureCopyWith<StudioTimelineFeedFailure> get copyWith => _$StudioTimelineFeedFailureCopyWithImpl<StudioTimelineFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineFeedFailure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $StudioTimelineFeedFailureCopyWith<$Res> implements $StudioTimelineFeedFrameCopyWith<$Res> {
  factory $StudioTimelineFeedFailureCopyWith(StudioTimelineFeedFailure value, $Res Function(StudioTimelineFeedFailure) _then) = _$StudioTimelineFeedFailureCopyWithImpl;
@useResult
$Res call({
 StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$StudioTimelineFeedFailureCopyWithImpl<$Res>
    implements $StudioTimelineFeedFailureCopyWith<$Res> {
  _$StudioTimelineFeedFailureCopyWithImpl(this._self, this._then);

  final StudioTimelineFeedFailure _self;
  final $Res Function(StudioTimelineFeedFailure) _then;

/// Create a copy of StudioTimelineFeedFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(StudioTimelineFeedFailure(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of StudioTimelineFeedFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class StudioTimelineFeedClosed extends StudioTimelineFeedFrame {
  const StudioTimelineFeedClosed(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineFeedClosed);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc
mixin _$StudioTimelineFeedEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineFeedEvent);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $StudioTimelineFeedEventCopyWith<$Res>  {
$StudioTimelineFeedEventCopyWith(StudioTimelineFeedEvent _, $Res Function(StudioTimelineFeedEvent) __);
}


/// Adds pattern-matching-related methods to [StudioTimelineFeedEvent].
extension StudioTimelineFeedEventPatterns on StudioTimelineFeedEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StudioTimelineFeedBaseline value)?  baseline,TResult Function( StudioTimelineFeedUpdate value)?  update,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StudioTimelineFeedBaseline() when baseline != null:
return baseline(_that);case StudioTimelineFeedUpdate() when update != null:
return update(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StudioTimelineFeedBaseline value)  baseline,required TResult Function( StudioTimelineFeedUpdate value)  update,}){
final _that = this;
switch (_that) {
case StudioTimelineFeedBaseline():
return baseline(_that);case StudioTimelineFeedUpdate():
return update(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StudioTimelineFeedBaseline value)?  baseline,TResult? Function( StudioTimelineFeedUpdate value)?  update,}){
final _that = this;
switch (_that) {
case StudioTimelineFeedBaseline() when baseline != null:
return baseline(_that);case StudioTimelineFeedUpdate() when update != null:
return update(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( StudioTimelineBaseline baseline)?  baseline,TResult Function( StudioTimelineUpdate update)?  update,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StudioTimelineFeedBaseline() when baseline != null:
return baseline(_that.baseline);case StudioTimelineFeedUpdate() when update != null:
return update(_that.update);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( StudioTimelineBaseline baseline)  baseline,required TResult Function( StudioTimelineUpdate update)  update,}) {final _that = this;
switch (_that) {
case StudioTimelineFeedBaseline():
return baseline(_that.baseline);case StudioTimelineFeedUpdate():
return update(_that.update);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( StudioTimelineBaseline baseline)?  baseline,TResult? Function( StudioTimelineUpdate update)?  update,}) {final _that = this;
switch (_that) {
case StudioTimelineFeedBaseline() when baseline != null:
return baseline(_that.baseline);case StudioTimelineFeedUpdate() when update != null:
return update(_that.update);case _:
  return null;

}
}

}

/// @nodoc


class StudioTimelineFeedBaseline extends StudioTimelineFeedEvent {
  const StudioTimelineFeedBaseline({required this.baseline}): super._();


 final  StudioTimelineBaseline baseline;

/// Create a copy of StudioTimelineFeedEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineFeedBaselineCopyWith<StudioTimelineFeedBaseline> get copyWith => _$StudioTimelineFeedBaselineCopyWithImpl<StudioTimelineFeedBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineFeedBaseline&&(identical(other.baseline, baseline) || other.baseline == baseline));
}


@override
int get hashCode {
    return Object.hash(runtimeType,baseline);
}



}

/// @nodoc
abstract mixin class $StudioTimelineFeedBaselineCopyWith<$Res> implements $StudioTimelineFeedEventCopyWith<$Res> {
  factory $StudioTimelineFeedBaselineCopyWith(StudioTimelineFeedBaseline value, $Res Function(StudioTimelineFeedBaseline) _then) = _$StudioTimelineFeedBaselineCopyWithImpl;
@useResult
$Res call({
 StudioTimelineBaseline baseline
});


$StudioTimelineBaselineCopyWith<$Res> get baseline;

}
/// @nodoc
class _$StudioTimelineFeedBaselineCopyWithImpl<$Res>
    implements $StudioTimelineFeedBaselineCopyWith<$Res> {
  _$StudioTimelineFeedBaselineCopyWithImpl(this._self, this._then);

  final StudioTimelineFeedBaseline _self;
  final $Res Function(StudioTimelineFeedBaseline) _then;

/// Create a copy of StudioTimelineFeedEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? baseline = null,}) {
  return _then(StudioTimelineFeedBaseline(
baseline: null == baseline ? _self.baseline : baseline // ignore: cast_nullable_to_non_nullable
as StudioTimelineBaseline,
  ));
}

/// Create a copy of StudioTimelineFeedEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelineBaselineCopyWith<$Res> get baseline {

  return $StudioTimelineBaselineCopyWith<$Res>(_self.baseline, (value) {
    return _then(_self.copyWith(baseline: value));
  });
}
}

/// @nodoc


class StudioTimelineFeedUpdate extends StudioTimelineFeedEvent {
  const StudioTimelineFeedUpdate({required this.update}): super._();


 final  StudioTimelineUpdate update;

/// Create a copy of StudioTimelineFeedEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioTimelineFeedUpdateCopyWith<StudioTimelineFeedUpdate> get copyWith => _$StudioTimelineFeedUpdateCopyWithImpl<StudioTimelineFeedUpdate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioTimelineFeedUpdate&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,update);
}



}

/// @nodoc
abstract mixin class $StudioTimelineFeedUpdateCopyWith<$Res> implements $StudioTimelineFeedEventCopyWith<$Res> {
  factory $StudioTimelineFeedUpdateCopyWith(StudioTimelineFeedUpdate value, $Res Function(StudioTimelineFeedUpdate) _then) = _$StudioTimelineFeedUpdateCopyWithImpl;
@useResult
$Res call({
 StudioTimelineUpdate update
});


$StudioTimelineUpdateCopyWith<$Res> get update;

}
/// @nodoc
class _$StudioTimelineFeedUpdateCopyWithImpl<$Res>
    implements $StudioTimelineFeedUpdateCopyWith<$Res> {
  _$StudioTimelineFeedUpdateCopyWithImpl(this._self, this._then);

  final StudioTimelineFeedUpdate _self;
  final $Res Function(StudioTimelineFeedUpdate) _then;

/// Create a copy of StudioTimelineFeedEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? update = null,}) {
  return _then(StudioTimelineFeedUpdate(
update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as StudioTimelineUpdate,
  ));
}

/// Create a copy of StudioTimelineFeedEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioTimelineUpdateCopyWith<$Res> get update {

  return $StudioTimelineUpdateCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

// dart format on
