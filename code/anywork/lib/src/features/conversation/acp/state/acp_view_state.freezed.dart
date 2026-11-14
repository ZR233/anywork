// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcpStartComposerViewState {

 String get workspaceId; String get text; String? get accountId; String? get serviceName; String? get brandKey; bool get submitting; bool get serviceEnabled; List<AttachmentDraftView> get stagedAttachments; String? get failureMessage;
/// Create a copy of AcpStartComposerViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpStartComposerViewStateCopyWith<AcpStartComposerViewState> get copyWith => _$AcpStartComposerViewStateCopyWithImpl<AcpStartComposerViewState>(this as AcpStartComposerViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpStartComposerViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpStartComposerViewState&&(identical(other.workspaceId, _this.workspaceId) || other.workspaceId == _this.workspaceId)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.serviceName, _this.serviceName) || other.serviceName == _this.serviceName)&&(identical(other.brandKey, _this.brandKey) || other.brandKey == _this.brandKey)&&(identical(other.submitting, _this.submitting) || other.submitting == _this.submitting)&&(identical(other.serviceEnabled, _this.serviceEnabled) || other.serviceEnabled == _this.serviceEnabled)&&const DeepCollectionEquality().equals(other.stagedAttachments, _this.stagedAttachments)&&(identical(other.failureMessage, _this.failureMessage) || other.failureMessage == _this.failureMessage));
}


@override
int get hashCode {
  final _this = this as AcpStartComposerViewState;
  return Object.hash(runtimeType,_this.workspaceId,_this.text,_this.accountId,_this.serviceName,_this.brandKey,_this.submitting,_this.serviceEnabled,const DeepCollectionEquality().hash(_this.stagedAttachments),_this.failureMessage);
}

@override
String toString() {
  final _this = this as AcpStartComposerViewState;
  return 'AcpStartComposerViewState(workspaceId: ${_this.workspaceId}, text: ${_this.text}, accountId: ${_this.accountId}, serviceName: ${_this.serviceName}, brandKey: ${_this.brandKey}, submitting: ${_this.submitting}, serviceEnabled: ${_this.serviceEnabled}, stagedAttachments: ${_this.stagedAttachments}, failureMessage: ${_this.failureMessage})';
}


}

/// @nodoc
abstract mixin class $AcpStartComposerViewStateCopyWith<$Res>  {
  factory $AcpStartComposerViewStateCopyWith(AcpStartComposerViewState value, $Res Function(AcpStartComposerViewState) _then) = _$AcpStartComposerViewStateCopyWithImpl;
@useResult
$Res call({
 String workspaceId, String text, String? accountId, String? serviceName, String? brandKey, bool submitting, bool serviceEnabled, List<AttachmentDraftView> stagedAttachments, String? failureMessage
});




}
/// @nodoc
class _$AcpStartComposerViewStateCopyWithImpl<$Res>
    implements $AcpStartComposerViewStateCopyWith<$Res> {
  _$AcpStartComposerViewStateCopyWithImpl(this._self, this._then);

  final AcpStartComposerViewState _self;
  final $Res Function(AcpStartComposerViewState) _then;

/// Create a copy of AcpStartComposerViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? workspaceId = null,Object? text = null,Object? accountId = freezed,Object? serviceName = freezed,Object? brandKey = freezed,Object? submitting = null,Object? serviceEnabled = null,Object? stagedAttachments = null,Object? failureMessage = freezed,}) {
  return _then(AcpStartComposerViewState(
workspaceId: null == workspaceId ? _self.workspaceId : workspaceId // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,serviceName: freezed == serviceName ? _self.serviceName : serviceName // ignore: cast_nullable_to_non_nullable
as String?,brandKey: freezed == brandKey ? _self.brandKey : brandKey // ignore: cast_nullable_to_non_nullable
as String?,submitting: null == submitting ? _self.submitting : submitting // ignore: cast_nullable_to_non_nullable
as bool,serviceEnabled: null == serviceEnabled ? _self.serviceEnabled : serviceEnabled // ignore: cast_nullable_to_non_nullable
as bool,stagedAttachments: null == stagedAttachments ? _self.stagedAttachments : stagedAttachments // ignore: cast_nullable_to_non_nullable
as List<AttachmentDraftView>,failureMessage: freezed == failureMessage ? _self.failureMessage : failureMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpStartComposerViewState].
extension AcpStartComposerViewStatePatterns on AcpStartComposerViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpStartComposerViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpStartComposerViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpStartComposerViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpStartComposerViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpStartComposerViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpStartComposerViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String workspaceId,  String text,  String? accountId,  String? serviceName,  String? brandKey,  bool submitting,  bool serviceEnabled,  List<AttachmentDraftView> stagedAttachments,  String? failureMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpStartComposerViewState() when $default != null:
return $default(_that.workspaceId,_that.text,_that.accountId,_that.serviceName,_that.brandKey,_that.submitting,_that.serviceEnabled,_that.stagedAttachments,_that.failureMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String workspaceId,  String text,  String? accountId,  String? serviceName,  String? brandKey,  bool submitting,  bool serviceEnabled,  List<AttachmentDraftView> stagedAttachments,  String? failureMessage)  $default,) {final _that = this;
switch (_that) {
case _AcpStartComposerViewState():
return $default(_that.workspaceId,_that.text,_that.accountId,_that.serviceName,_that.brandKey,_that.submitting,_that.serviceEnabled,_that.stagedAttachments,_that.failureMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String workspaceId,  String text,  String? accountId,  String? serviceName,  String? brandKey,  bool submitting,  bool serviceEnabled,  List<AttachmentDraftView> stagedAttachments,  String? failureMessage)?  $default,) {final _that = this;
switch (_that) {
case _AcpStartComposerViewState() when $default != null:
return $default(_that.workspaceId,_that.text,_that.accountId,_that.serviceName,_that.brandKey,_that.submitting,_that.serviceEnabled,_that.stagedAttachments,_that.failureMessage);case _:
  return null;

}
}

}

/// @nodoc


class _AcpStartComposerViewState extends AcpStartComposerViewState {
  const _AcpStartComposerViewState({required this.workspaceId, required this.text, this.accountId, this.serviceName, this.brandKey, this.submitting = false, this.serviceEnabled = false,  List<AttachmentDraftView> stagedAttachments = const <AttachmentDraftView>[], this.failureMessage}): _stagedAttachments = stagedAttachments,super._();


@override final  String workspaceId;
@override final  String text;
@override final  String? accountId;
@override final  String? serviceName;
@override final  String? brandKey;
@override@JsonKey() final  bool submitting;
@override@JsonKey() final  bool serviceEnabled;
 final  List<AttachmentDraftView> _stagedAttachments;
@override@JsonKey() List<AttachmentDraftView> get stagedAttachments {
  if (_stagedAttachments is EqualUnmodifiableListView) return _stagedAttachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_stagedAttachments);
}

@override final  String? failureMessage;

/// Create a copy of AcpStartComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpStartComposerViewStateCopyWith<_AcpStartComposerViewState> get copyWith => __$AcpStartComposerViewStateCopyWithImpl<_AcpStartComposerViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpStartComposerViewState&&(identical(other.workspaceId, workspaceId) || other.workspaceId == workspaceId)&&(identical(other.text, text) || other.text == text)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.serviceName, serviceName) || other.serviceName == serviceName)&&(identical(other.brandKey, brandKey) || other.brandKey == brandKey)&&(identical(other.submitting, submitting) || other.submitting == submitting)&&(identical(other.serviceEnabled, serviceEnabled) || other.serviceEnabled == serviceEnabled)&&const DeepCollectionEquality().equals(other.stagedAttachments, _stagedAttachments)&&(identical(other.failureMessage, failureMessage) || other.failureMessage == failureMessage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,workspaceId,text,accountId,serviceName,brandKey,submitting,serviceEnabled,const DeepCollectionEquality().hash(_stagedAttachments),failureMessage);
}

@override
String toString() {
    return 'AcpStartComposerViewState(workspaceId: $workspaceId, text: $text, accountId: $accountId, serviceName: $serviceName, brandKey: $brandKey, submitting: $submitting, serviceEnabled: $serviceEnabled, stagedAttachments: $stagedAttachments, failureMessage: $failureMessage)';
}


}

/// @nodoc
abstract mixin class _$AcpStartComposerViewStateCopyWith<$Res> implements $AcpStartComposerViewStateCopyWith<$Res> {
  factory _$AcpStartComposerViewStateCopyWith(_AcpStartComposerViewState value, $Res Function(_AcpStartComposerViewState) _then) = __$AcpStartComposerViewStateCopyWithImpl;
@override @useResult
$Res call({
 String workspaceId, String text, String? accountId, String? serviceName, String? brandKey, bool submitting, bool serviceEnabled, List<AttachmentDraftView> stagedAttachments, String? failureMessage
});




}
/// @nodoc
class __$AcpStartComposerViewStateCopyWithImpl<$Res>
    implements _$AcpStartComposerViewStateCopyWith<$Res> {
  __$AcpStartComposerViewStateCopyWithImpl(this._self, this._then);

  final _AcpStartComposerViewState _self;
  final $Res Function(_AcpStartComposerViewState) _then;

/// Create a copy of AcpStartComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? workspaceId = null,Object? text = null,Object? accountId = freezed,Object? serviceName = freezed,Object? brandKey = freezed,Object? submitting = null,Object? serviceEnabled = null,Object? stagedAttachments = null,Object? failureMessage = freezed,}) {
  return _then(_AcpStartComposerViewState(
workspaceId: null == workspaceId ? _self.workspaceId : workspaceId // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,serviceName: freezed == serviceName ? _self.serviceName : serviceName // ignore: cast_nullable_to_non_nullable
as String?,brandKey: freezed == brandKey ? _self.brandKey : brandKey // ignore: cast_nullable_to_non_nullable
as String?,submitting: null == submitting ? _self.submitting : submitting // ignore: cast_nullable_to_non_nullable
as bool,serviceEnabled: null == serviceEnabled ? _self.serviceEnabled : serviceEnabled // ignore: cast_nullable_to_non_nullable
as bool,stagedAttachments: null == stagedAttachments ? _self._stagedAttachments : stagedAttachments // ignore: cast_nullable_to_non_nullable
as List<AttachmentDraftView>,failureMessage: freezed == failureMessage ? _self.failureMessage : failureMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AcpTimelineHeaderViewState {

 bool get loading; bool get ready; bool get disconnected; bool get observationEnded; int get itemCount; bool get hasConversationalContent; bool get hasPlan; List<AcpCapabilityKind> get capabilities; String? get errorMessage; AcpGapKind? get gapKind; AcpHistoryOriginKind? get historyKind;
/// Create a copy of AcpTimelineHeaderViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpTimelineHeaderViewStateCopyWith<AcpTimelineHeaderViewState> get copyWith => _$AcpTimelineHeaderViewStateCopyWithImpl<AcpTimelineHeaderViewState>(this as AcpTimelineHeaderViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpTimelineHeaderViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpTimelineHeaderViewState&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.ready, _this.ready) || other.ready == _this.ready)&&(identical(other.disconnected, _this.disconnected) || other.disconnected == _this.disconnected)&&(identical(other.observationEnded, _this.observationEnded) || other.observationEnded == _this.observationEnded)&&(identical(other.itemCount, _this.itemCount) || other.itemCount == _this.itemCount)&&(identical(other.hasConversationalContent, _this.hasConversationalContent) || other.hasConversationalContent == _this.hasConversationalContent)&&(identical(other.hasPlan, _this.hasPlan) || other.hasPlan == _this.hasPlan)&&const DeepCollectionEquality().equals(other.capabilities, _this.capabilities)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage)&&(identical(other.gapKind, _this.gapKind) || other.gapKind == _this.gapKind)&&(identical(other.historyKind, _this.historyKind) || other.historyKind == _this.historyKind));
}


@override
int get hashCode {
  final _this = this as AcpTimelineHeaderViewState;
  return Object.hash(runtimeType,_this.loading,_this.ready,_this.disconnected,_this.observationEnded,_this.itemCount,_this.hasConversationalContent,_this.hasPlan,const DeepCollectionEquality().hash(_this.capabilities),_this.errorMessage,_this.gapKind,_this.historyKind);
}

@override
String toString() {
  final _this = this as AcpTimelineHeaderViewState;
  return 'AcpTimelineHeaderViewState(loading: ${_this.loading}, ready: ${_this.ready}, disconnected: ${_this.disconnected}, observationEnded: ${_this.observationEnded}, itemCount: ${_this.itemCount}, hasConversationalContent: ${_this.hasConversationalContent}, hasPlan: ${_this.hasPlan}, capabilities: ${_this.capabilities}, errorMessage: ${_this.errorMessage}, gapKind: ${_this.gapKind}, historyKind: ${_this.historyKind})';
}


}

/// @nodoc
abstract mixin class $AcpTimelineHeaderViewStateCopyWith<$Res>  {
  factory $AcpTimelineHeaderViewStateCopyWith(AcpTimelineHeaderViewState value, $Res Function(AcpTimelineHeaderViewState) _then) = _$AcpTimelineHeaderViewStateCopyWithImpl;
@useResult
$Res call({
 bool loading, bool ready, bool disconnected, bool observationEnded, int itemCount, bool hasConversationalContent, bool hasPlan, List<AcpCapabilityKind> capabilities, String? errorMessage, AcpGapKind? gapKind, AcpHistoryOriginKind? historyKind
});




}
/// @nodoc
class _$AcpTimelineHeaderViewStateCopyWithImpl<$Res>
    implements $AcpTimelineHeaderViewStateCopyWith<$Res> {
  _$AcpTimelineHeaderViewStateCopyWithImpl(this._self, this._then);

  final AcpTimelineHeaderViewState _self;
  final $Res Function(AcpTimelineHeaderViewState) _then;

/// Create a copy of AcpTimelineHeaderViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? loading = null,Object? ready = null,Object? disconnected = null,Object? observationEnded = null,Object? itemCount = null,Object? hasConversationalContent = null,Object? hasPlan = null,Object? capabilities = null,Object? errorMessage = freezed,Object? gapKind = freezed,Object? historyKind = freezed,}) {
  return _then(AcpTimelineHeaderViewState(
loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,ready: null == ready ? _self.ready : ready // ignore: cast_nullable_to_non_nullable
as bool,disconnected: null == disconnected ? _self.disconnected : disconnected // ignore: cast_nullable_to_non_nullable
as bool,observationEnded: null == observationEnded ? _self.observationEnded : observationEnded // ignore: cast_nullable_to_non_nullable
as bool,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,hasConversationalContent: null == hasConversationalContent ? _self.hasConversationalContent : hasConversationalContent // ignore: cast_nullable_to_non_nullable
as bool,hasPlan: null == hasPlan ? _self.hasPlan : hasPlan // ignore: cast_nullable_to_non_nullable
as bool,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as List<AcpCapabilityKind>,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,gapKind: freezed == gapKind ? _self.gapKind : gapKind // ignore: cast_nullable_to_non_nullable
as AcpGapKind?,historyKind: freezed == historyKind ? _self.historyKind : historyKind // ignore: cast_nullable_to_non_nullable
as AcpHistoryOriginKind?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpTimelineHeaderViewState].
extension AcpTimelineHeaderViewStatePatterns on AcpTimelineHeaderViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpTimelineHeaderViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpTimelineHeaderViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpTimelineHeaderViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpTimelineHeaderViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpTimelineHeaderViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpTimelineHeaderViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool loading,  bool ready,  bool disconnected,  bool observationEnded,  int itemCount,  bool hasConversationalContent,  bool hasPlan,  List<AcpCapabilityKind> capabilities,  String? errorMessage,  AcpGapKind? gapKind,  AcpHistoryOriginKind? historyKind)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpTimelineHeaderViewState() when $default != null:
return $default(_that.loading,_that.ready,_that.disconnected,_that.observationEnded,_that.itemCount,_that.hasConversationalContent,_that.hasPlan,_that.capabilities,_that.errorMessage,_that.gapKind,_that.historyKind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool loading,  bool ready,  bool disconnected,  bool observationEnded,  int itemCount,  bool hasConversationalContent,  bool hasPlan,  List<AcpCapabilityKind> capabilities,  String? errorMessage,  AcpGapKind? gapKind,  AcpHistoryOriginKind? historyKind)  $default,) {final _that = this;
switch (_that) {
case _AcpTimelineHeaderViewState():
return $default(_that.loading,_that.ready,_that.disconnected,_that.observationEnded,_that.itemCount,_that.hasConversationalContent,_that.hasPlan,_that.capabilities,_that.errorMessage,_that.gapKind,_that.historyKind);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool loading,  bool ready,  bool disconnected,  bool observationEnded,  int itemCount,  bool hasConversationalContent,  bool hasPlan,  List<AcpCapabilityKind> capabilities,  String? errorMessage,  AcpGapKind? gapKind,  AcpHistoryOriginKind? historyKind)?  $default,) {final _that = this;
switch (_that) {
case _AcpTimelineHeaderViewState() when $default != null:
return $default(_that.loading,_that.ready,_that.disconnected,_that.observationEnded,_that.itemCount,_that.hasConversationalContent,_that.hasPlan,_that.capabilities,_that.errorMessage,_that.gapKind,_that.historyKind);case _:
  return null;

}
}

}

/// @nodoc


class _AcpTimelineHeaderViewState implements AcpTimelineHeaderViewState {
  const _AcpTimelineHeaderViewState({this.loading = true, this.ready = false, this.disconnected = false, this.observationEnded = false, this.itemCount = 0, this.hasConversationalContent = false, this.hasPlan = false,  List<AcpCapabilityKind> capabilities = const <AcpCapabilityKind>[], this.errorMessage, this.gapKind, this.historyKind}): _capabilities = capabilities;


@override@JsonKey() final  bool loading;
@override@JsonKey() final  bool ready;
@override@JsonKey() final  bool disconnected;
@override@JsonKey() final  bool observationEnded;
@override@JsonKey() final  int itemCount;
@override@JsonKey() final  bool hasConversationalContent;
@override@JsonKey() final  bool hasPlan;
 final  List<AcpCapabilityKind> _capabilities;
@override@JsonKey() List<AcpCapabilityKind> get capabilities {
  if (_capabilities is EqualUnmodifiableListView) return _capabilities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_capabilities);
}

@override final  String? errorMessage;
@override final  AcpGapKind? gapKind;
@override final  AcpHistoryOriginKind? historyKind;

/// Create a copy of AcpTimelineHeaderViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpTimelineHeaderViewStateCopyWith<_AcpTimelineHeaderViewState> get copyWith => __$AcpTimelineHeaderViewStateCopyWithImpl<_AcpTimelineHeaderViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpTimelineHeaderViewState&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.ready, ready) || other.ready == ready)&&(identical(other.disconnected, disconnected) || other.disconnected == disconnected)&&(identical(other.observationEnded, observationEnded) || other.observationEnded == observationEnded)&&(identical(other.itemCount, itemCount) || other.itemCount == itemCount)&&(identical(other.hasConversationalContent, hasConversationalContent) || other.hasConversationalContent == hasConversationalContent)&&(identical(other.hasPlan, hasPlan) || other.hasPlan == hasPlan)&&const DeepCollectionEquality().equals(other.capabilities, _capabilities)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.gapKind, gapKind) || other.gapKind == gapKind)&&(identical(other.historyKind, historyKind) || other.historyKind == historyKind));
}


@override
int get hashCode {
    return Object.hash(runtimeType,loading,ready,disconnected,observationEnded,itemCount,hasConversationalContent,hasPlan,const DeepCollectionEquality().hash(_capabilities),errorMessage,gapKind,historyKind);
}

@override
String toString() {
    return 'AcpTimelineHeaderViewState(loading: $loading, ready: $ready, disconnected: $disconnected, observationEnded: $observationEnded, itemCount: $itemCount, hasConversationalContent: $hasConversationalContent, hasPlan: $hasPlan, capabilities: $capabilities, errorMessage: $errorMessage, gapKind: $gapKind, historyKind: $historyKind)';
}


}

/// @nodoc
abstract mixin class _$AcpTimelineHeaderViewStateCopyWith<$Res> implements $AcpTimelineHeaderViewStateCopyWith<$Res> {
  factory _$AcpTimelineHeaderViewStateCopyWith(_AcpTimelineHeaderViewState value, $Res Function(_AcpTimelineHeaderViewState) _then) = __$AcpTimelineHeaderViewStateCopyWithImpl;
@override @useResult
$Res call({
 bool loading, bool ready, bool disconnected, bool observationEnded, int itemCount, bool hasConversationalContent, bool hasPlan, List<AcpCapabilityKind> capabilities, String? errorMessage, AcpGapKind? gapKind, AcpHistoryOriginKind? historyKind
});




}
/// @nodoc
class __$AcpTimelineHeaderViewStateCopyWithImpl<$Res>
    implements _$AcpTimelineHeaderViewStateCopyWith<$Res> {
  __$AcpTimelineHeaderViewStateCopyWithImpl(this._self, this._then);

  final _AcpTimelineHeaderViewState _self;
  final $Res Function(_AcpTimelineHeaderViewState) _then;

/// Create a copy of AcpTimelineHeaderViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? loading = null,Object? ready = null,Object? disconnected = null,Object? observationEnded = null,Object? itemCount = null,Object? hasConversationalContent = null,Object? hasPlan = null,Object? capabilities = null,Object? errorMessage = freezed,Object? gapKind = freezed,Object? historyKind = freezed,}) {
  return _then(_AcpTimelineHeaderViewState(
loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,ready: null == ready ? _self.ready : ready // ignore: cast_nullable_to_non_nullable
as bool,disconnected: null == disconnected ? _self.disconnected : disconnected // ignore: cast_nullable_to_non_nullable
as bool,observationEnded: null == observationEnded ? _self.observationEnded : observationEnded // ignore: cast_nullable_to_non_nullable
as bool,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,hasConversationalContent: null == hasConversationalContent ? _self.hasConversationalContent : hasConversationalContent // ignore: cast_nullable_to_non_nullable
as bool,hasPlan: null == hasPlan ? _self.hasPlan : hasPlan // ignore: cast_nullable_to_non_nullable
as bool,capabilities: null == capabilities ? _self._capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as List<AcpCapabilityKind>,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,gapKind: freezed == gapKind ? _self.gapKind : gapKind // ignore: cast_nullable_to_non_nullable
as AcpGapKind?,historyKind: freezed == historyKind ? _self.historyKind : historyKind // ignore: cast_nullable_to_non_nullable
as AcpHistoryOriginKind?,
  ));
}


}

/// @nodoc
mixin _$AcpContentBlockPresentation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpContentBlockPresentation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AcpContentBlockPresentation()';
}


}

/// @nodoc
class $AcpContentBlockPresentationCopyWith<$Res>  {
$AcpContentBlockPresentationCopyWith(AcpContentBlockPresentation _, $Res Function(AcpContentBlockPresentation) __);
}


/// Adds pattern-matching-related methods to [AcpContentBlockPresentation].
extension AcpContentBlockPresentationPatterns on AcpContentBlockPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpTextBlockPresentation value)?  text,TResult Function( AcpImageBlockPresentation value)?  image,TResult Function( AcpAudioBlockPresentation value)?  audio,TResult Function( AcpResourceLinkBlockPresentation value)?  resourceLink,TResult Function( AcpTextResourceBlockPresentation value)?  textResource,TResult Function( AcpBlobResourceBlockPresentation value)?  blobResource,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpTextBlockPresentation() when text != null:
return text(_that);case AcpImageBlockPresentation() when image != null:
return image(_that);case AcpAudioBlockPresentation() when audio != null:
return audio(_that);case AcpResourceLinkBlockPresentation() when resourceLink != null:
return resourceLink(_that);case AcpTextResourceBlockPresentation() when textResource != null:
return textResource(_that);case AcpBlobResourceBlockPresentation() when blobResource != null:
return blobResource(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpTextBlockPresentation value)  text,required TResult Function( AcpImageBlockPresentation value)  image,required TResult Function( AcpAudioBlockPresentation value)  audio,required TResult Function( AcpResourceLinkBlockPresentation value)  resourceLink,required TResult Function( AcpTextResourceBlockPresentation value)  textResource,required TResult Function( AcpBlobResourceBlockPresentation value)  blobResource,}){
final _that = this;
switch (_that) {
case AcpTextBlockPresentation():
return text(_that);case AcpImageBlockPresentation():
return image(_that);case AcpAudioBlockPresentation():
return audio(_that);case AcpResourceLinkBlockPresentation():
return resourceLink(_that);case AcpTextResourceBlockPresentation():
return textResource(_that);case AcpBlobResourceBlockPresentation():
return blobResource(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpTextBlockPresentation value)?  text,TResult? Function( AcpImageBlockPresentation value)?  image,TResult? Function( AcpAudioBlockPresentation value)?  audio,TResult? Function( AcpResourceLinkBlockPresentation value)?  resourceLink,TResult? Function( AcpTextResourceBlockPresentation value)?  textResource,TResult? Function( AcpBlobResourceBlockPresentation value)?  blobResource,}){
final _that = this;
switch (_that) {
case AcpTextBlockPresentation() when text != null:
return text(_that);case AcpImageBlockPresentation() when image != null:
return image(_that);case AcpAudioBlockPresentation() when audio != null:
return audio(_that);case AcpResourceLinkBlockPresentation() when resourceLink != null:
return resourceLink(_that);case AcpTextResourceBlockPresentation() when textResource != null:
return textResource(_that);case AcpBlobResourceBlockPresentation() when blobResource != null:
return blobResource(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  text,TResult Function( String cacheKey,  String dataBase64,  String mimeType,  String? uri)?  image,TResult Function( String mimeType)?  audio,TResult Function( String label,  String uri,  String? description,  String? mimeType,  bool canOpenExternal)?  resourceLink,TResult Function( String uri,  String text,  String? mimeType)?  textResource,TResult Function( String uri,  String? mimeType,  int byteCount)?  blobResource,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpTextBlockPresentation() when text != null:
return text(_that.text);case AcpImageBlockPresentation() when image != null:
return image(_that.cacheKey,_that.dataBase64,_that.mimeType,_that.uri);case AcpAudioBlockPresentation() when audio != null:
return audio(_that.mimeType);case AcpResourceLinkBlockPresentation() when resourceLink != null:
return resourceLink(_that.label,_that.uri,_that.description,_that.mimeType,_that.canOpenExternal);case AcpTextResourceBlockPresentation() when textResource != null:
return textResource(_that.uri,_that.text,_that.mimeType);case AcpBlobResourceBlockPresentation() when blobResource != null:
return blobResource(_that.uri,_that.mimeType,_that.byteCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  text,required TResult Function( String cacheKey,  String dataBase64,  String mimeType,  String? uri)  image,required TResult Function( String mimeType)  audio,required TResult Function( String label,  String uri,  String? description,  String? mimeType,  bool canOpenExternal)  resourceLink,required TResult Function( String uri,  String text,  String? mimeType)  textResource,required TResult Function( String uri,  String? mimeType,  int byteCount)  blobResource,}) {final _that = this;
switch (_that) {
case AcpTextBlockPresentation():
return text(_that.text);case AcpImageBlockPresentation():
return image(_that.cacheKey,_that.dataBase64,_that.mimeType,_that.uri);case AcpAudioBlockPresentation():
return audio(_that.mimeType);case AcpResourceLinkBlockPresentation():
return resourceLink(_that.label,_that.uri,_that.description,_that.mimeType,_that.canOpenExternal);case AcpTextResourceBlockPresentation():
return textResource(_that.uri,_that.text,_that.mimeType);case AcpBlobResourceBlockPresentation():
return blobResource(_that.uri,_that.mimeType,_that.byteCount);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  text,TResult? Function( String cacheKey,  String dataBase64,  String mimeType,  String? uri)?  image,TResult? Function( String mimeType)?  audio,TResult? Function( String label,  String uri,  String? description,  String? mimeType,  bool canOpenExternal)?  resourceLink,TResult? Function( String uri,  String text,  String? mimeType)?  textResource,TResult? Function( String uri,  String? mimeType,  int byteCount)?  blobResource,}) {final _that = this;
switch (_that) {
case AcpTextBlockPresentation() when text != null:
return text(_that.text);case AcpImageBlockPresentation() when image != null:
return image(_that.cacheKey,_that.dataBase64,_that.mimeType,_that.uri);case AcpAudioBlockPresentation() when audio != null:
return audio(_that.mimeType);case AcpResourceLinkBlockPresentation() when resourceLink != null:
return resourceLink(_that.label,_that.uri,_that.description,_that.mimeType,_that.canOpenExternal);case AcpTextResourceBlockPresentation() when textResource != null:
return textResource(_that.uri,_that.text,_that.mimeType);case AcpBlobResourceBlockPresentation() when blobResource != null:
return blobResource(_that.uri,_that.mimeType,_that.byteCount);case _:
  return null;

}
}

}

/// @nodoc


class AcpTextBlockPresentation implements AcpContentBlockPresentation {
  const AcpTextBlockPresentation({required this.text});


 final  String text;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpTextBlockPresentationCopyWith<AcpTextBlockPresentation> get copyWith => _$AcpTextBlockPresentationCopyWithImpl<AcpTextBlockPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpTextBlockPresentation&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'AcpContentBlockPresentation.text(text: $text)';
}


}

/// @nodoc
abstract mixin class $AcpTextBlockPresentationCopyWith<$Res> implements $AcpContentBlockPresentationCopyWith<$Res> {
  factory $AcpTextBlockPresentationCopyWith(AcpTextBlockPresentation value, $Res Function(AcpTextBlockPresentation) _then) = _$AcpTextBlockPresentationCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$AcpTextBlockPresentationCopyWithImpl<$Res>
    implements $AcpTextBlockPresentationCopyWith<$Res> {
  _$AcpTextBlockPresentationCopyWithImpl(this._self, this._then);

  final AcpTextBlockPresentation _self;
  final $Res Function(AcpTextBlockPresentation) _then;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(AcpTextBlockPresentation(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AcpImageBlockPresentation implements AcpContentBlockPresentation {
  const AcpImageBlockPresentation({required this.cacheKey, required this.dataBase64, required this.mimeType, this.uri});


 final  String cacheKey;
 final  String dataBase64;
 final  String mimeType;
 final  String? uri;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpImageBlockPresentationCopyWith<AcpImageBlockPresentation> get copyWith => _$AcpImageBlockPresentationCopyWithImpl<AcpImageBlockPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpImageBlockPresentation&&(identical(other.cacheKey, cacheKey) || other.cacheKey == cacheKey)&&(identical(other.dataBase64, dataBase64) || other.dataBase64 == dataBase64)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.uri, uri) || other.uri == uri));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cacheKey,dataBase64,mimeType,uri);
}

@override
String toString() {
    return 'AcpContentBlockPresentation.image(cacheKey: $cacheKey, dataBase64: $dataBase64, mimeType: $mimeType, uri: $uri)';
}


}

/// @nodoc
abstract mixin class $AcpImageBlockPresentationCopyWith<$Res> implements $AcpContentBlockPresentationCopyWith<$Res> {
  factory $AcpImageBlockPresentationCopyWith(AcpImageBlockPresentation value, $Res Function(AcpImageBlockPresentation) _then) = _$AcpImageBlockPresentationCopyWithImpl;
@useResult
$Res call({
 String cacheKey, String dataBase64, String mimeType, String? uri
});




}
/// @nodoc
class _$AcpImageBlockPresentationCopyWithImpl<$Res>
    implements $AcpImageBlockPresentationCopyWith<$Res> {
  _$AcpImageBlockPresentationCopyWithImpl(this._self, this._then);

  final AcpImageBlockPresentation _self;
  final $Res Function(AcpImageBlockPresentation) _then;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cacheKey = null,Object? dataBase64 = null,Object? mimeType = null,Object? uri = freezed,}) {
  return _then(AcpImageBlockPresentation(
cacheKey: null == cacheKey ? _self.cacheKey : cacheKey // ignore: cast_nullable_to_non_nullable
as String,dataBase64: null == dataBase64 ? _self.dataBase64 : dataBase64 // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,uri: freezed == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class AcpAudioBlockPresentation implements AcpContentBlockPresentation {
  const AcpAudioBlockPresentation({required this.mimeType});


 final  String mimeType;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAudioBlockPresentationCopyWith<AcpAudioBlockPresentation> get copyWith => _$AcpAudioBlockPresentationCopyWithImpl<AcpAudioBlockPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAudioBlockPresentation&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mimeType);
}

@override
String toString() {
    return 'AcpContentBlockPresentation.audio(mimeType: $mimeType)';
}


}

/// @nodoc
abstract mixin class $AcpAudioBlockPresentationCopyWith<$Res> implements $AcpContentBlockPresentationCopyWith<$Res> {
  factory $AcpAudioBlockPresentationCopyWith(AcpAudioBlockPresentation value, $Res Function(AcpAudioBlockPresentation) _then) = _$AcpAudioBlockPresentationCopyWithImpl;
@useResult
$Res call({
 String mimeType
});




}
/// @nodoc
class _$AcpAudioBlockPresentationCopyWithImpl<$Res>
    implements $AcpAudioBlockPresentationCopyWith<$Res> {
  _$AcpAudioBlockPresentationCopyWithImpl(this._self, this._then);

  final AcpAudioBlockPresentation _self;
  final $Res Function(AcpAudioBlockPresentation) _then;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? mimeType = null,}) {
  return _then(AcpAudioBlockPresentation(
mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AcpResourceLinkBlockPresentation implements AcpContentBlockPresentation {
  const AcpResourceLinkBlockPresentation({required this.label, required this.uri, this.description, this.mimeType, this.canOpenExternal = false});


 final  String label;
 final  String uri;
 final  String? description;
 final  String? mimeType;
@JsonKey() final  bool canOpenExternal;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpResourceLinkBlockPresentationCopyWith<AcpResourceLinkBlockPresentation> get copyWith => _$AcpResourceLinkBlockPresentationCopyWithImpl<AcpResourceLinkBlockPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpResourceLinkBlockPresentation&&(identical(other.label, label) || other.label == label)&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.description, description) || other.description == description)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.canOpenExternal, canOpenExternal) || other.canOpenExternal == canOpenExternal));
}


@override
int get hashCode {
    return Object.hash(runtimeType,label,uri,description,mimeType,canOpenExternal);
}

@override
String toString() {
    return 'AcpContentBlockPresentation.resourceLink(label: $label, uri: $uri, description: $description, mimeType: $mimeType, canOpenExternal: $canOpenExternal)';
}


}

/// @nodoc
abstract mixin class $AcpResourceLinkBlockPresentationCopyWith<$Res> implements $AcpContentBlockPresentationCopyWith<$Res> {
  factory $AcpResourceLinkBlockPresentationCopyWith(AcpResourceLinkBlockPresentation value, $Res Function(AcpResourceLinkBlockPresentation) _then) = _$AcpResourceLinkBlockPresentationCopyWithImpl;
@useResult
$Res call({
 String label, String uri, String? description, String? mimeType, bool canOpenExternal
});




}
/// @nodoc
class _$AcpResourceLinkBlockPresentationCopyWithImpl<$Res>
    implements $AcpResourceLinkBlockPresentationCopyWith<$Res> {
  _$AcpResourceLinkBlockPresentationCopyWithImpl(this._self, this._then);

  final AcpResourceLinkBlockPresentation _self;
  final $Res Function(AcpResourceLinkBlockPresentation) _then;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? label = null,Object? uri = null,Object? description = freezed,Object? mimeType = freezed,Object? canOpenExternal = null,}) {
  return _then(AcpResourceLinkBlockPresentation(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,canOpenExternal: null == canOpenExternal ? _self.canOpenExternal : canOpenExternal // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class AcpTextResourceBlockPresentation implements AcpContentBlockPresentation {
  const AcpTextResourceBlockPresentation({required this.uri, required this.text, this.mimeType});


 final  String uri;
 final  String text;
 final  String? mimeType;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpTextResourceBlockPresentationCopyWith<AcpTextResourceBlockPresentation> get copyWith => _$AcpTextResourceBlockPresentationCopyWithImpl<AcpTextResourceBlockPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpTextResourceBlockPresentation&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.text, text) || other.text == text)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType));
}


@override
int get hashCode {
    return Object.hash(runtimeType,uri,text,mimeType);
}

@override
String toString() {
    return 'AcpContentBlockPresentation.textResource(uri: $uri, text: $text, mimeType: $mimeType)';
}


}

/// @nodoc
abstract mixin class $AcpTextResourceBlockPresentationCopyWith<$Res> implements $AcpContentBlockPresentationCopyWith<$Res> {
  factory $AcpTextResourceBlockPresentationCopyWith(AcpTextResourceBlockPresentation value, $Res Function(AcpTextResourceBlockPresentation) _then) = _$AcpTextResourceBlockPresentationCopyWithImpl;
@useResult
$Res call({
 String uri, String text, String? mimeType
});




}
/// @nodoc
class _$AcpTextResourceBlockPresentationCopyWithImpl<$Res>
    implements $AcpTextResourceBlockPresentationCopyWith<$Res> {
  _$AcpTextResourceBlockPresentationCopyWithImpl(this._self, this._then);

  final AcpTextResourceBlockPresentation _self;
  final $Res Function(AcpTextResourceBlockPresentation) _then;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? uri = null,Object? text = null,Object? mimeType = freezed,}) {
  return _then(AcpTextResourceBlockPresentation(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class AcpBlobResourceBlockPresentation implements AcpContentBlockPresentation {
  const AcpBlobResourceBlockPresentation({required this.uri, this.mimeType, required this.byteCount});


 final  String uri;
 final  String? mimeType;
 final  int byteCount;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpBlobResourceBlockPresentationCopyWith<AcpBlobResourceBlockPresentation> get copyWith => _$AcpBlobResourceBlockPresentationCopyWithImpl<AcpBlobResourceBlockPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpBlobResourceBlockPresentation&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.byteCount, byteCount) || other.byteCount == byteCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,uri,mimeType,byteCount);
}

@override
String toString() {
    return 'AcpContentBlockPresentation.blobResource(uri: $uri, mimeType: $mimeType, byteCount: $byteCount)';
}


}

/// @nodoc
abstract mixin class $AcpBlobResourceBlockPresentationCopyWith<$Res> implements $AcpContentBlockPresentationCopyWith<$Res> {
  factory $AcpBlobResourceBlockPresentationCopyWith(AcpBlobResourceBlockPresentation value, $Res Function(AcpBlobResourceBlockPresentation) _then) = _$AcpBlobResourceBlockPresentationCopyWithImpl;
@useResult
$Res call({
 String uri, String? mimeType, int byteCount
});




}
/// @nodoc
class _$AcpBlobResourceBlockPresentationCopyWithImpl<$Res>
    implements $AcpBlobResourceBlockPresentationCopyWith<$Res> {
  _$AcpBlobResourceBlockPresentationCopyWithImpl(this._self, this._then);

  final AcpBlobResourceBlockPresentation _self;
  final $Res Function(AcpBlobResourceBlockPresentation) _then;

/// Create a copy of AcpContentBlockPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? uri = null,Object? mimeType = freezed,Object? byteCount = null,}) {
  return _then(AcpBlobResourceBlockPresentation(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,byteCount: null == byteCount ? _self.byteCount : byteCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AcpImagePayload {

 String get cacheKey; String get dataBase64; String get mimeType; String? get uri;
/// Create a copy of AcpImagePayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpImagePayloadCopyWith<AcpImagePayload> get copyWith => _$AcpImagePayloadCopyWithImpl<AcpImagePayload>(this as AcpImagePayload, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpImagePayload;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpImagePayload&&(identical(other.cacheKey, _this.cacheKey) || other.cacheKey == _this.cacheKey)&&(identical(other.dataBase64, _this.dataBase64) || other.dataBase64 == _this.dataBase64)&&(identical(other.mimeType, _this.mimeType) || other.mimeType == _this.mimeType)&&(identical(other.uri, _this.uri) || other.uri == _this.uri));
}


@override
int get hashCode {
  final _this = this as AcpImagePayload;
  return Object.hash(runtimeType,_this.cacheKey,_this.dataBase64,_this.mimeType,_this.uri);
}

@override
String toString() {
  final _this = this as AcpImagePayload;
  return 'AcpImagePayload(cacheKey: ${_this.cacheKey}, dataBase64: ${_this.dataBase64}, mimeType: ${_this.mimeType}, uri: ${_this.uri})';
}


}

/// @nodoc
abstract mixin class $AcpImagePayloadCopyWith<$Res>  {
  factory $AcpImagePayloadCopyWith(AcpImagePayload value, $Res Function(AcpImagePayload) _then) = _$AcpImagePayloadCopyWithImpl;
@useResult
$Res call({
 String cacheKey, String dataBase64, String mimeType, String? uri
});




}
/// @nodoc
class _$AcpImagePayloadCopyWithImpl<$Res>
    implements $AcpImagePayloadCopyWith<$Res> {
  _$AcpImagePayloadCopyWithImpl(this._self, this._then);

  final AcpImagePayload _self;
  final $Res Function(AcpImagePayload) _then;

/// Create a copy of AcpImagePayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? cacheKey = null,Object? dataBase64 = null,Object? mimeType = null,Object? uri = freezed,}) {
  return _then(AcpImagePayload(
cacheKey: null == cacheKey ? _self.cacheKey : cacheKey // ignore: cast_nullable_to_non_nullable
as String,dataBase64: null == dataBase64 ? _self.dataBase64 : dataBase64 // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,uri: freezed == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpImagePayload].
extension AcpImagePayloadPatterns on AcpImagePayload {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpImagePayload value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpImagePayload() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpImagePayload value)  $default,){
final _that = this;
switch (_that) {
case _AcpImagePayload():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpImagePayload value)?  $default,){
final _that = this;
switch (_that) {
case _AcpImagePayload() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String cacheKey,  String dataBase64,  String mimeType,  String? uri)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpImagePayload() when $default != null:
return $default(_that.cacheKey,_that.dataBase64,_that.mimeType,_that.uri);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String cacheKey,  String dataBase64,  String mimeType,  String? uri)  $default,) {final _that = this;
switch (_that) {
case _AcpImagePayload():
return $default(_that.cacheKey,_that.dataBase64,_that.mimeType,_that.uri);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String cacheKey,  String dataBase64,  String mimeType,  String? uri)?  $default,) {final _that = this;
switch (_that) {
case _AcpImagePayload() when $default != null:
return $default(_that.cacheKey,_that.dataBase64,_that.mimeType,_that.uri);case _:
  return null;

}
}

}

/// @nodoc


class _AcpImagePayload implements AcpImagePayload {
  const _AcpImagePayload({required this.cacheKey, required this.dataBase64, required this.mimeType, this.uri});


@override final  String cacheKey;
@override final  String dataBase64;
@override final  String mimeType;
@override final  String? uri;

/// Create a copy of AcpImagePayload
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpImagePayloadCopyWith<_AcpImagePayload> get copyWith => __$AcpImagePayloadCopyWithImpl<_AcpImagePayload>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpImagePayload&&(identical(other.cacheKey, cacheKey) || other.cacheKey == cacheKey)&&(identical(other.dataBase64, dataBase64) || other.dataBase64 == dataBase64)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.uri, uri) || other.uri == uri));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cacheKey,dataBase64,mimeType,uri);
}

@override
String toString() {
    return 'AcpImagePayload(cacheKey: $cacheKey, dataBase64: $dataBase64, mimeType: $mimeType, uri: $uri)';
}


}

/// @nodoc
abstract mixin class _$AcpImagePayloadCopyWith<$Res> implements $AcpImagePayloadCopyWith<$Res> {
  factory _$AcpImagePayloadCopyWith(_AcpImagePayload value, $Res Function(_AcpImagePayload) _then) = __$AcpImagePayloadCopyWithImpl;
@override @useResult
$Res call({
 String cacheKey, String dataBase64, String mimeType, String? uri
});




}
/// @nodoc
class __$AcpImagePayloadCopyWithImpl<$Res>
    implements _$AcpImagePayloadCopyWith<$Res> {
  __$AcpImagePayloadCopyWithImpl(this._self, this._then);

  final _AcpImagePayload _self;
  final $Res Function(_AcpImagePayload) _then;

/// Create a copy of AcpImagePayload
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cacheKey = null,Object? dataBase64 = null,Object? mimeType = null,Object? uri = freezed,}) {
  return _then(_AcpImagePayload(
cacheKey: null == cacheKey ? _self.cacheKey : cacheKey // ignore: cast_nullable_to_non_nullable
as String,dataBase64: null == dataBase64 ? _self.dataBase64 : dataBase64 // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,uri: freezed == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AcpDecodedImagePresentation {

 Uint8List get bytes; ThreadAttachmentView get attachment;
/// Create a copy of AcpDecodedImagePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpDecodedImagePresentationCopyWith<AcpDecodedImagePresentation> get copyWith => _$AcpDecodedImagePresentationCopyWithImpl<AcpDecodedImagePresentation>(this as AcpDecodedImagePresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpDecodedImagePresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpDecodedImagePresentation&&const DeepCollectionEquality().equals(other.bytes, _this.bytes)&&(identical(other.attachment, _this.attachment) || other.attachment == _this.attachment));
}


@override
int get hashCode {
  final _this = this as AcpDecodedImagePresentation;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.bytes),_this.attachment);
}

@override
String toString() {
  final _this = this as AcpDecodedImagePresentation;
  return 'AcpDecodedImagePresentation(bytes: ${_this.bytes}, attachment: ${_this.attachment})';
}


}

/// @nodoc
abstract mixin class $AcpDecodedImagePresentationCopyWith<$Res>  {
  factory $AcpDecodedImagePresentationCopyWith(AcpDecodedImagePresentation value, $Res Function(AcpDecodedImagePresentation) _then) = _$AcpDecodedImagePresentationCopyWithImpl;
@useResult
$Res call({
 Uint8List bytes, ThreadAttachmentView attachment
});




}
/// @nodoc
class _$AcpDecodedImagePresentationCopyWithImpl<$Res>
    implements $AcpDecodedImagePresentationCopyWith<$Res> {
  _$AcpDecodedImagePresentationCopyWithImpl(this._self, this._then);

  final AcpDecodedImagePresentation _self;
  final $Res Function(AcpDecodedImagePresentation) _then;

/// Create a copy of AcpDecodedImagePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? bytes = null,Object? attachment = null,}) {
  return _then(AcpDecodedImagePresentation(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,attachment: null == attachment ? _self.attachment : attachment // ignore: cast_nullable_to_non_nullable
as ThreadAttachmentView,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpDecodedImagePresentation].
extension AcpDecodedImagePresentationPatterns on AcpDecodedImagePresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpDecodedImagePresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpDecodedImagePresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpDecodedImagePresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpDecodedImagePresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpDecodedImagePresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpDecodedImagePresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Uint8List bytes,  ThreadAttachmentView attachment)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpDecodedImagePresentation() when $default != null:
return $default(_that.bytes,_that.attachment);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Uint8List bytes,  ThreadAttachmentView attachment)  $default,) {final _that = this;
switch (_that) {
case _AcpDecodedImagePresentation():
return $default(_that.bytes,_that.attachment);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Uint8List bytes,  ThreadAttachmentView attachment)?  $default,) {final _that = this;
switch (_that) {
case _AcpDecodedImagePresentation() when $default != null:
return $default(_that.bytes,_that.attachment);case _:
  return null;

}
}

}

/// @nodoc


class _AcpDecodedImagePresentation implements AcpDecodedImagePresentation {
  const _AcpDecodedImagePresentation({required this.bytes, required this.attachment});


@override final  Uint8List bytes;
@override final  ThreadAttachmentView attachment;

/// Create a copy of AcpDecodedImagePresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpDecodedImagePresentationCopyWith<_AcpDecodedImagePresentation> get copyWith => __$AcpDecodedImagePresentationCopyWithImpl<_AcpDecodedImagePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpDecodedImagePresentation&&const DeepCollectionEquality().equals(other.bytes, bytes)&&(identical(other.attachment, attachment) || other.attachment == attachment));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(bytes),attachment);
}

@override
String toString() {
    return 'AcpDecodedImagePresentation(bytes: $bytes, attachment: $attachment)';
}


}

/// @nodoc
abstract mixin class _$AcpDecodedImagePresentationCopyWith<$Res> implements $AcpDecodedImagePresentationCopyWith<$Res> {
  factory _$AcpDecodedImagePresentationCopyWith(_AcpDecodedImagePresentation value, $Res Function(_AcpDecodedImagePresentation) _then) = __$AcpDecodedImagePresentationCopyWithImpl;
@override @useResult
$Res call({
 Uint8List bytes, ThreadAttachmentView attachment
});




}
/// @nodoc
class __$AcpDecodedImagePresentationCopyWithImpl<$Res>
    implements _$AcpDecodedImagePresentationCopyWith<$Res> {
  __$AcpDecodedImagePresentationCopyWithImpl(this._self, this._then);

  final _AcpDecodedImagePresentation _self;
  final $Res Function(_AcpDecodedImagePresentation) _then;

/// Create a copy of AcpDecodedImagePresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? bytes = null,Object? attachment = null,}) {
  return _then(_AcpDecodedImagePresentation(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,attachment: null == attachment ? _self.attachment : attachment // ignore: cast_nullable_to_non_nullable
as ThreadAttachmentView,
  ));
}


}

/// @nodoc
mixin _$AcpUpdatePresentation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpUpdatePresentation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AcpUpdatePresentation()';
}


}

/// @nodoc
class $AcpUpdatePresentationCopyWith<$Res>  {
$AcpUpdatePresentationCopyWith(AcpUpdatePresentation _, $Res Function(AcpUpdatePresentation) __);
}


/// Adds pattern-matching-related methods to [AcpUpdatePresentation].
extension AcpUpdatePresentationPatterns on AcpUpdatePresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpNoticeUpdatePresentation value)?  notice,TResult Function( AcpUsageUpdatePresentation value)?  usage,TResult Function( AcpCompactionUpdatePresentation value)?  compaction,TResult Function( AcpCommandsUpdatePresentation value)?  availableCommands,TResult Function( AcpSessionInfoUpdatePresentation value)?  sessionInfo,TResult Function( AcpSupersededUpdatePresentation value)?  superseded,TResult Function( AcpGenericUpdatePresentation value)?  generic,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpNoticeUpdatePresentation() when notice != null:
return notice(_that);case AcpUsageUpdatePresentation() when usage != null:
return usage(_that);case AcpCompactionUpdatePresentation() when compaction != null:
return compaction(_that);case AcpCommandsUpdatePresentation() when availableCommands != null:
return availableCommands(_that);case AcpSessionInfoUpdatePresentation() when sessionInfo != null:
return sessionInfo(_that);case AcpSupersededUpdatePresentation() when superseded != null:
return superseded(_that);case AcpGenericUpdatePresentation() when generic != null:
return generic(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpNoticeUpdatePresentation value)  notice,required TResult Function( AcpUsageUpdatePresentation value)  usage,required TResult Function( AcpCompactionUpdatePresentation value)  compaction,required TResult Function( AcpCommandsUpdatePresentation value)  availableCommands,required TResult Function( AcpSessionInfoUpdatePresentation value)  sessionInfo,required TResult Function( AcpSupersededUpdatePresentation value)  superseded,required TResult Function( AcpGenericUpdatePresentation value)  generic,}){
final _that = this;
switch (_that) {
case AcpNoticeUpdatePresentation():
return notice(_that);case AcpUsageUpdatePresentation():
return usage(_that);case AcpCompactionUpdatePresentation():
return compaction(_that);case AcpCommandsUpdatePresentation():
return availableCommands(_that);case AcpSessionInfoUpdatePresentation():
return sessionInfo(_that);case AcpSupersededUpdatePresentation():
return superseded(_that);case AcpGenericUpdatePresentation():
return generic(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpNoticeUpdatePresentation value)?  notice,TResult? Function( AcpUsageUpdatePresentation value)?  usage,TResult? Function( AcpCompactionUpdatePresentation value)?  compaction,TResult? Function( AcpCommandsUpdatePresentation value)?  availableCommands,TResult? Function( AcpSessionInfoUpdatePresentation value)?  sessionInfo,TResult? Function( AcpSupersededUpdatePresentation value)?  superseded,TResult? Function( AcpGenericUpdatePresentation value)?  generic,}){
final _that = this;
switch (_that) {
case AcpNoticeUpdatePresentation() when notice != null:
return notice(_that);case AcpUsageUpdatePresentation() when usage != null:
return usage(_that);case AcpCompactionUpdatePresentation() when compaction != null:
return compaction(_that);case AcpCommandsUpdatePresentation() when availableCommands != null:
return availableCommands(_that);case AcpSessionInfoUpdatePresentation() when sessionInfo != null:
return sessionInfo(_that);case AcpSupersededUpdatePresentation() when superseded != null:
return superseded(_that);case AcpGenericUpdatePresentation() when generic != null:
return generic(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String title,  String? description)?  notice,TResult Function( String usedFormatted,  String sizeFormatted,  String? costLabel)?  usage,TResult Function( String statusLabel,  String? errorMessage)?  compaction,TResult Function( List<({String description, String name,})> commands)?  availableCommands,TResult Function()?  sessionInfo,TResult Function()?  superseded,TResult Function()?  generic,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpNoticeUpdatePresentation() when notice != null:
return notice(_that.title,_that.description);case AcpUsageUpdatePresentation() when usage != null:
return usage(_that.usedFormatted,_that.sizeFormatted,_that.costLabel);case AcpCompactionUpdatePresentation() when compaction != null:
return compaction(_that.statusLabel,_that.errorMessage);case AcpCommandsUpdatePresentation() when availableCommands != null:
return availableCommands(_that.commands);case AcpSessionInfoUpdatePresentation() when sessionInfo != null:
return sessionInfo();case AcpSupersededUpdatePresentation() when superseded != null:
return superseded();case AcpGenericUpdatePresentation() when generic != null:
return generic();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String title,  String? description)  notice,required TResult Function( String usedFormatted,  String sizeFormatted,  String? costLabel)  usage,required TResult Function( String statusLabel,  String? errorMessage)  compaction,required TResult Function( List<({String description, String name,})> commands)  availableCommands,required TResult Function()  sessionInfo,required TResult Function()  superseded,required TResult Function()  generic,}) {final _that = this;
switch (_that) {
case AcpNoticeUpdatePresentation():
return notice(_that.title,_that.description);case AcpUsageUpdatePresentation():
return usage(_that.usedFormatted,_that.sizeFormatted,_that.costLabel);case AcpCompactionUpdatePresentation():
return compaction(_that.statusLabel,_that.errorMessage);case AcpCommandsUpdatePresentation():
return availableCommands(_that.commands);case AcpSessionInfoUpdatePresentation():
return sessionInfo();case AcpSupersededUpdatePresentation():
return superseded();case AcpGenericUpdatePresentation():
return generic();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String title,  String? description)?  notice,TResult? Function( String usedFormatted,  String sizeFormatted,  String? costLabel)?  usage,TResult? Function( String statusLabel,  String? errorMessage)?  compaction,TResult? Function( List<({String description, String name,})> commands)?  availableCommands,TResult? Function()?  sessionInfo,TResult? Function()?  superseded,TResult? Function()?  generic,}) {final _that = this;
switch (_that) {
case AcpNoticeUpdatePresentation() when notice != null:
return notice(_that.title,_that.description);case AcpUsageUpdatePresentation() when usage != null:
return usage(_that.usedFormatted,_that.sizeFormatted,_that.costLabel);case AcpCompactionUpdatePresentation() when compaction != null:
return compaction(_that.statusLabel,_that.errorMessage);case AcpCommandsUpdatePresentation() when availableCommands != null:
return availableCommands(_that.commands);case AcpSessionInfoUpdatePresentation() when sessionInfo != null:
return sessionInfo();case AcpSupersededUpdatePresentation() when superseded != null:
return superseded();case AcpGenericUpdatePresentation() when generic != null:
return generic();case _:
  return null;

}
}

}

/// @nodoc


class AcpNoticeUpdatePresentation implements AcpUpdatePresentation {
  const AcpNoticeUpdatePresentation({required this.title, this.description});


 final  String title;
 final  String? description;

/// Create a copy of AcpUpdatePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpNoticeUpdatePresentationCopyWith<AcpNoticeUpdatePresentation> get copyWith => _$AcpNoticeUpdatePresentationCopyWithImpl<AcpNoticeUpdatePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpNoticeUpdatePresentation&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,description);
}

@override
String toString() {
    return 'AcpUpdatePresentation.notice(title: $title, description: $description)';
}


}

/// @nodoc
abstract mixin class $AcpNoticeUpdatePresentationCopyWith<$Res> implements $AcpUpdatePresentationCopyWith<$Res> {
  factory $AcpNoticeUpdatePresentationCopyWith(AcpNoticeUpdatePresentation value, $Res Function(AcpNoticeUpdatePresentation) _then) = _$AcpNoticeUpdatePresentationCopyWithImpl;
@useResult
$Res call({
 String title, String? description
});




}
/// @nodoc
class _$AcpNoticeUpdatePresentationCopyWithImpl<$Res>
    implements $AcpNoticeUpdatePresentationCopyWith<$Res> {
  _$AcpNoticeUpdatePresentationCopyWithImpl(this._self, this._then);

  final AcpNoticeUpdatePresentation _self;
  final $Res Function(AcpNoticeUpdatePresentation) _then;

/// Create a copy of AcpUpdatePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = null,Object? description = freezed,}) {
  return _then(AcpNoticeUpdatePresentation(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class AcpUsageUpdatePresentation implements AcpUpdatePresentation {
  const AcpUsageUpdatePresentation({required this.usedFormatted, required this.sizeFormatted, this.costLabel});


 final  String usedFormatted;
 final  String sizeFormatted;
 final  String? costLabel;

/// Create a copy of AcpUpdatePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpUsageUpdatePresentationCopyWith<AcpUsageUpdatePresentation> get copyWith => _$AcpUsageUpdatePresentationCopyWithImpl<AcpUsageUpdatePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpUsageUpdatePresentation&&(identical(other.usedFormatted, usedFormatted) || other.usedFormatted == usedFormatted)&&(identical(other.sizeFormatted, sizeFormatted) || other.sizeFormatted == sizeFormatted)&&(identical(other.costLabel, costLabel) || other.costLabel == costLabel));
}


@override
int get hashCode {
    return Object.hash(runtimeType,usedFormatted,sizeFormatted,costLabel);
}

@override
String toString() {
    return 'AcpUpdatePresentation.usage(usedFormatted: $usedFormatted, sizeFormatted: $sizeFormatted, costLabel: $costLabel)';
}


}

/// @nodoc
abstract mixin class $AcpUsageUpdatePresentationCopyWith<$Res> implements $AcpUpdatePresentationCopyWith<$Res> {
  factory $AcpUsageUpdatePresentationCopyWith(AcpUsageUpdatePresentation value, $Res Function(AcpUsageUpdatePresentation) _then) = _$AcpUsageUpdatePresentationCopyWithImpl;
@useResult
$Res call({
 String usedFormatted, String sizeFormatted, String? costLabel
});




}
/// @nodoc
class _$AcpUsageUpdatePresentationCopyWithImpl<$Res>
    implements $AcpUsageUpdatePresentationCopyWith<$Res> {
  _$AcpUsageUpdatePresentationCopyWithImpl(this._self, this._then);

  final AcpUsageUpdatePresentation _self;
  final $Res Function(AcpUsageUpdatePresentation) _then;

/// Create a copy of AcpUpdatePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? usedFormatted = null,Object? sizeFormatted = null,Object? costLabel = freezed,}) {
  return _then(AcpUsageUpdatePresentation(
usedFormatted: null == usedFormatted ? _self.usedFormatted : usedFormatted // ignore: cast_nullable_to_non_nullable
as String,sizeFormatted: null == sizeFormatted ? _self.sizeFormatted : sizeFormatted // ignore: cast_nullable_to_non_nullable
as String,costLabel: freezed == costLabel ? _self.costLabel : costLabel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class AcpCompactionUpdatePresentation implements AcpUpdatePresentation {
  const AcpCompactionUpdatePresentation({required this.statusLabel, this.errorMessage});


 final  String statusLabel;
 final  String? errorMessage;

/// Create a copy of AcpUpdatePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpCompactionUpdatePresentationCopyWith<AcpCompactionUpdatePresentation> get copyWith => _$AcpCompactionUpdatePresentationCopyWithImpl<AcpCompactionUpdatePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpCompactionUpdatePresentation&&(identical(other.statusLabel, statusLabel) || other.statusLabel == statusLabel)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,statusLabel,errorMessage);
}

@override
String toString() {
    return 'AcpUpdatePresentation.compaction(statusLabel: $statusLabel, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $AcpCompactionUpdatePresentationCopyWith<$Res> implements $AcpUpdatePresentationCopyWith<$Res> {
  factory $AcpCompactionUpdatePresentationCopyWith(AcpCompactionUpdatePresentation value, $Res Function(AcpCompactionUpdatePresentation) _then) = _$AcpCompactionUpdatePresentationCopyWithImpl;
@useResult
$Res call({
 String statusLabel, String? errorMessage
});




}
/// @nodoc
class _$AcpCompactionUpdatePresentationCopyWithImpl<$Res>
    implements $AcpCompactionUpdatePresentationCopyWith<$Res> {
  _$AcpCompactionUpdatePresentationCopyWithImpl(this._self, this._then);

  final AcpCompactionUpdatePresentation _self;
  final $Res Function(AcpCompactionUpdatePresentation) _then;

/// Create a copy of AcpUpdatePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? statusLabel = null,Object? errorMessage = freezed,}) {
  return _then(AcpCompactionUpdatePresentation(
statusLabel: null == statusLabel ? _self.statusLabel : statusLabel // ignore: cast_nullable_to_non_nullable
as String,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class AcpCommandsUpdatePresentation implements AcpUpdatePresentation {
  const AcpCommandsUpdatePresentation({required  List<({String description, String name,})> commands}): _commands = commands;


 final  List<({String description, String name,})> _commands;
 List<({String description, String name,})> get commands {
  if (_commands is EqualUnmodifiableListView) return _commands;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_commands);
}


/// Create a copy of AcpUpdatePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpCommandsUpdatePresentationCopyWith<AcpCommandsUpdatePresentation> get copyWith => _$AcpCommandsUpdatePresentationCopyWithImpl<AcpCommandsUpdatePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpCommandsUpdatePresentation&&const DeepCollectionEquality().equals(other.commands, _commands));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_commands));
}

@override
String toString() {
    return 'AcpUpdatePresentation.availableCommands(commands: $commands)';
}


}

/// @nodoc
abstract mixin class $AcpCommandsUpdatePresentationCopyWith<$Res> implements $AcpUpdatePresentationCopyWith<$Res> {
  factory $AcpCommandsUpdatePresentationCopyWith(AcpCommandsUpdatePresentation value, $Res Function(AcpCommandsUpdatePresentation) _then) = _$AcpCommandsUpdatePresentationCopyWithImpl;
@useResult
$Res call({
 List<({String description, String name,})> commands
});




}
/// @nodoc
class _$AcpCommandsUpdatePresentationCopyWithImpl<$Res>
    implements $AcpCommandsUpdatePresentationCopyWith<$Res> {
  _$AcpCommandsUpdatePresentationCopyWithImpl(this._self, this._then);

  final AcpCommandsUpdatePresentation _self;
  final $Res Function(AcpCommandsUpdatePresentation) _then;

/// Create a copy of AcpUpdatePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? commands = null,}) {
  return _then(AcpCommandsUpdatePresentation(
commands: null == commands ? _self._commands : commands // ignore: cast_nullable_to_non_nullable
as List<({String description, String name,})>,
  ));
}


}

/// @nodoc


class AcpSessionInfoUpdatePresentation implements AcpUpdatePresentation {
  const AcpSessionInfoUpdatePresentation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpSessionInfoUpdatePresentation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AcpUpdatePresentation.sessionInfo()';
}


}




/// @nodoc


class AcpSupersededUpdatePresentation implements AcpUpdatePresentation {
  const AcpSupersededUpdatePresentation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpSupersededUpdatePresentation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AcpUpdatePresentation.superseded()';
}


}




/// @nodoc


class AcpGenericUpdatePresentation implements AcpUpdatePresentation {
  const AcpGenericUpdatePresentation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpGenericUpdatePresentation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AcpUpdatePresentation.generic()';
}


}




/// @nodoc
mixin _$AcpTimelineItemPresentation {

 String get id;
/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpTimelineItemPresentationCopyWith<AcpTimelineItemPresentation> get copyWith => _$AcpTimelineItemPresentationCopyWithImpl<AcpTimelineItemPresentation>(this as AcpTimelineItemPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpTimelineItemPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpTimelineItemPresentation&&(identical(other.id, _this.id) || other.id == _this.id));
}


@override
int get hashCode {
  final _this = this as AcpTimelineItemPresentation;
  return Object.hash(runtimeType,_this.id);
}

@override
String toString() {
  final _this = this as AcpTimelineItemPresentation;
  return 'AcpTimelineItemPresentation(id: ${_this.id})';
}


}

/// @nodoc
abstract mixin class $AcpTimelineItemPresentationCopyWith<$Res>  {
  factory $AcpTimelineItemPresentationCopyWith(AcpTimelineItemPresentation value, $Res Function(AcpTimelineItemPresentation) _then) = _$AcpTimelineItemPresentationCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$AcpTimelineItemPresentationCopyWithImpl<$Res>
    implements $AcpTimelineItemPresentationCopyWith<$Res> {
  _$AcpTimelineItemPresentationCopyWithImpl(this._self, this._then);

  final AcpTimelineItemPresentation _self;
  final $Res Function(AcpTimelineItemPresentation) _then;

/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpTimelineItemPresentation].
extension AcpTimelineItemPresentationPatterns on AcpTimelineItemPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpTimelineUserMessage value)?  userMessage,TResult Function( AcpTimelineAssistantMessage value)?  assistantMessage,TResult Function( AcpTimelineThoughtItem value)?  thought,TResult Function( AcpTimelineToolCallItem value)?  toolCall,TResult Function( AcpTimelineSessionUpdateItem value)?  sessionUpdate,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpTimelineUserMessage() when userMessage != null:
return userMessage(_that);case AcpTimelineAssistantMessage() when assistantMessage != null:
return assistantMessage(_that);case AcpTimelineThoughtItem() when thought != null:
return thought(_that);case AcpTimelineToolCallItem() when toolCall != null:
return toolCall(_that);case AcpTimelineSessionUpdateItem() when sessionUpdate != null:
return sessionUpdate(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpTimelineUserMessage value)  userMessage,required TResult Function( AcpTimelineAssistantMessage value)  assistantMessage,required TResult Function( AcpTimelineThoughtItem value)  thought,required TResult Function( AcpTimelineToolCallItem value)  toolCall,required TResult Function( AcpTimelineSessionUpdateItem value)  sessionUpdate,}){
final _that = this;
switch (_that) {
case AcpTimelineUserMessage():
return userMessage(_that);case AcpTimelineAssistantMessage():
return assistantMessage(_that);case AcpTimelineThoughtItem():
return thought(_that);case AcpTimelineToolCallItem():
return toolCall(_that);case AcpTimelineSessionUpdateItem():
return sessionUpdate(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpTimelineUserMessage value)?  userMessage,TResult? Function( AcpTimelineAssistantMessage value)?  assistantMessage,TResult? Function( AcpTimelineThoughtItem value)?  thought,TResult? Function( AcpTimelineToolCallItem value)?  toolCall,TResult? Function( AcpTimelineSessionUpdateItem value)?  sessionUpdate,}){
final _that = this;
switch (_that) {
case AcpTimelineUserMessage() when userMessage != null:
return userMessage(_that);case AcpTimelineAssistantMessage() when assistantMessage != null:
return assistantMessage(_that);case AcpTimelineThoughtItem() when thought != null:
return thought(_that);case AcpTimelineToolCallItem() when toolCall != null:
return toolCall(_that);case AcpTimelineSessionUpdateItem() when sessionUpdate != null:
return sessionUpdate(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  List<AcpContentBlockPresentation> blocks)?  userMessage,TResult Function( String id,  List<AcpContentBlockPresentation> blocks)?  assistantMessage,TResult Function( String id,  String summary,  List<AcpContentBlockPresentation> blocks,  bool active)?  thought,TResult Function( String id,  String toolCallId,  TimelineToolPresentation tool,  AcpToolStatusKind status,  String? kindLabel,  List<String> locations,  List<String> terminals,  List<TimelinePatchDocument> diffs,  List<AcpContentBlockPresentation> contentBlocks)?  toolCall,TResult Function( String id,  AcpUpdatePresentation update)?  sessionUpdate,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpTimelineUserMessage() when userMessage != null:
return userMessage(_that.id,_that.blocks);case AcpTimelineAssistantMessage() when assistantMessage != null:
return assistantMessage(_that.id,_that.blocks);case AcpTimelineThoughtItem() when thought != null:
return thought(_that.id,_that.summary,_that.blocks,_that.active);case AcpTimelineToolCallItem() when toolCall != null:
return toolCall(_that.id,_that.toolCallId,_that.tool,_that.status,_that.kindLabel,_that.locations,_that.terminals,_that.diffs,_that.contentBlocks);case AcpTimelineSessionUpdateItem() when sessionUpdate != null:
return sessionUpdate(_that.id,_that.update);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  List<AcpContentBlockPresentation> blocks)  userMessage,required TResult Function( String id,  List<AcpContentBlockPresentation> blocks)  assistantMessage,required TResult Function( String id,  String summary,  List<AcpContentBlockPresentation> blocks,  bool active)  thought,required TResult Function( String id,  String toolCallId,  TimelineToolPresentation tool,  AcpToolStatusKind status,  String? kindLabel,  List<String> locations,  List<String> terminals,  List<TimelinePatchDocument> diffs,  List<AcpContentBlockPresentation> contentBlocks)  toolCall,required TResult Function( String id,  AcpUpdatePresentation update)  sessionUpdate,}) {final _that = this;
switch (_that) {
case AcpTimelineUserMessage():
return userMessage(_that.id,_that.blocks);case AcpTimelineAssistantMessage():
return assistantMessage(_that.id,_that.blocks);case AcpTimelineThoughtItem():
return thought(_that.id,_that.summary,_that.blocks,_that.active);case AcpTimelineToolCallItem():
return toolCall(_that.id,_that.toolCallId,_that.tool,_that.status,_that.kindLabel,_that.locations,_that.terminals,_that.diffs,_that.contentBlocks);case AcpTimelineSessionUpdateItem():
return sessionUpdate(_that.id,_that.update);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  List<AcpContentBlockPresentation> blocks)?  userMessage,TResult? Function( String id,  List<AcpContentBlockPresentation> blocks)?  assistantMessage,TResult? Function( String id,  String summary,  List<AcpContentBlockPresentation> blocks,  bool active)?  thought,TResult? Function( String id,  String toolCallId,  TimelineToolPresentation tool,  AcpToolStatusKind status,  String? kindLabel,  List<String> locations,  List<String> terminals,  List<TimelinePatchDocument> diffs,  List<AcpContentBlockPresentation> contentBlocks)?  toolCall,TResult? Function( String id,  AcpUpdatePresentation update)?  sessionUpdate,}) {final _that = this;
switch (_that) {
case AcpTimelineUserMessage() when userMessage != null:
return userMessage(_that.id,_that.blocks);case AcpTimelineAssistantMessage() when assistantMessage != null:
return assistantMessage(_that.id,_that.blocks);case AcpTimelineThoughtItem() when thought != null:
return thought(_that.id,_that.summary,_that.blocks,_that.active);case AcpTimelineToolCallItem() when toolCall != null:
return toolCall(_that.id,_that.toolCallId,_that.tool,_that.status,_that.kindLabel,_that.locations,_that.terminals,_that.diffs,_that.contentBlocks);case AcpTimelineSessionUpdateItem() when sessionUpdate != null:
return sessionUpdate(_that.id,_that.update);case _:
  return null;

}
}

}

/// @nodoc


class AcpTimelineUserMessage implements AcpTimelineItemPresentation {
  const AcpTimelineUserMessage({required this.id, required  List<AcpContentBlockPresentation> blocks}): _blocks = blocks;


@override final  String id;
 final  List<AcpContentBlockPresentation> _blocks;
 List<AcpContentBlockPresentation> get blocks {
  if (_blocks is EqualUnmodifiableListView) return _blocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blocks);
}


/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpTimelineUserMessageCopyWith<AcpTimelineUserMessage> get copyWith => _$AcpTimelineUserMessageCopyWithImpl<AcpTimelineUserMessage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpTimelineUserMessage&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.blocks, _blocks));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_blocks));
}

@override
String toString() {
    return 'AcpTimelineItemPresentation.userMessage(id: $id, blocks: $blocks)';
}


}

/// @nodoc
abstract mixin class $AcpTimelineUserMessageCopyWith<$Res> implements $AcpTimelineItemPresentationCopyWith<$Res> {
  factory $AcpTimelineUserMessageCopyWith(AcpTimelineUserMessage value, $Res Function(AcpTimelineUserMessage) _then) = _$AcpTimelineUserMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, List<AcpContentBlockPresentation> blocks
});




}
/// @nodoc
class _$AcpTimelineUserMessageCopyWithImpl<$Res>
    implements $AcpTimelineUserMessageCopyWith<$Res> {
  _$AcpTimelineUserMessageCopyWithImpl(this._self, this._then);

  final AcpTimelineUserMessage _self;
  final $Res Function(AcpTimelineUserMessage) _then;

/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? blocks = null,}) {
  return _then(AcpTimelineUserMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,blocks: null == blocks ? _self._blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<AcpContentBlockPresentation>,
  ));
}


}

/// @nodoc


class AcpTimelineAssistantMessage implements AcpTimelineItemPresentation {
  const AcpTimelineAssistantMessage({required this.id, required  List<AcpContentBlockPresentation> blocks}): _blocks = blocks;


@override final  String id;
 final  List<AcpContentBlockPresentation> _blocks;
 List<AcpContentBlockPresentation> get blocks {
  if (_blocks is EqualUnmodifiableListView) return _blocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blocks);
}


/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpTimelineAssistantMessageCopyWith<AcpTimelineAssistantMessage> get copyWith => _$AcpTimelineAssistantMessageCopyWithImpl<AcpTimelineAssistantMessage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpTimelineAssistantMessage&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.blocks, _blocks));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_blocks));
}

@override
String toString() {
    return 'AcpTimelineItemPresentation.assistantMessage(id: $id, blocks: $blocks)';
}


}

/// @nodoc
abstract mixin class $AcpTimelineAssistantMessageCopyWith<$Res> implements $AcpTimelineItemPresentationCopyWith<$Res> {
  factory $AcpTimelineAssistantMessageCopyWith(AcpTimelineAssistantMessage value, $Res Function(AcpTimelineAssistantMessage) _then) = _$AcpTimelineAssistantMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, List<AcpContentBlockPresentation> blocks
});




}
/// @nodoc
class _$AcpTimelineAssistantMessageCopyWithImpl<$Res>
    implements $AcpTimelineAssistantMessageCopyWith<$Res> {
  _$AcpTimelineAssistantMessageCopyWithImpl(this._self, this._then);

  final AcpTimelineAssistantMessage _self;
  final $Res Function(AcpTimelineAssistantMessage) _then;

/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? blocks = null,}) {
  return _then(AcpTimelineAssistantMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,blocks: null == blocks ? _self._blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<AcpContentBlockPresentation>,
  ));
}


}

/// @nodoc


class AcpTimelineThoughtItem implements AcpTimelineItemPresentation {
  const AcpTimelineThoughtItem({required this.id, required this.summary, required  List<AcpContentBlockPresentation> blocks, this.active = false}): _blocks = blocks;


@override final  String id;
 final  String summary;
 final  List<AcpContentBlockPresentation> _blocks;
 List<AcpContentBlockPresentation> get blocks {
  if (_blocks is EqualUnmodifiableListView) return _blocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blocks);
}

@JsonKey() final  bool active;

/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpTimelineThoughtItemCopyWith<AcpTimelineThoughtItem> get copyWith => _$AcpTimelineThoughtItemCopyWithImpl<AcpTimelineThoughtItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpTimelineThoughtItem&&(identical(other.id, id) || other.id == id)&&(identical(other.summary, summary) || other.summary == summary)&&const DeepCollectionEquality().equals(other.blocks, _blocks)&&(identical(other.active, active) || other.active == active));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,summary,const DeepCollectionEquality().hash(_blocks),active);
}

@override
String toString() {
    return 'AcpTimelineItemPresentation.thought(id: $id, summary: $summary, blocks: $blocks, active: $active)';
}


}

/// @nodoc
abstract mixin class $AcpTimelineThoughtItemCopyWith<$Res> implements $AcpTimelineItemPresentationCopyWith<$Res> {
  factory $AcpTimelineThoughtItemCopyWith(AcpTimelineThoughtItem value, $Res Function(AcpTimelineThoughtItem) _then) = _$AcpTimelineThoughtItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String summary, List<AcpContentBlockPresentation> blocks, bool active
});




}
/// @nodoc
class _$AcpTimelineThoughtItemCopyWithImpl<$Res>
    implements $AcpTimelineThoughtItemCopyWith<$Res> {
  _$AcpTimelineThoughtItemCopyWithImpl(this._self, this._then);

  final AcpTimelineThoughtItem _self;
  final $Res Function(AcpTimelineThoughtItem) _then;

/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? summary = null,Object? blocks = null,Object? active = null,}) {
  return _then(AcpTimelineThoughtItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,blocks: null == blocks ? _self._blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<AcpContentBlockPresentation>,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class AcpTimelineToolCallItem implements AcpTimelineItemPresentation {
  const AcpTimelineToolCallItem({required this.id, required this.toolCallId, required this.tool, required this.status, this.kindLabel,  List<String> locations = const <String>[],  List<String> terminals = const <String>[],  List<TimelinePatchDocument> diffs = const <TimelinePatchDocument>[],  List<AcpContentBlockPresentation> contentBlocks = const <AcpContentBlockPresentation>[]}): _locations = locations,_terminals = terminals,_diffs = diffs,_contentBlocks = contentBlocks;


@override final  String id;
 final  String toolCallId;
 final  TimelineToolPresentation tool;
 final  AcpToolStatusKind status;
 final  String? kindLabel;
 final  List<String> _locations;
@JsonKey() List<String> get locations {
  if (_locations is EqualUnmodifiableListView) return _locations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_locations);
}

 final  List<String> _terminals;
@JsonKey() List<String> get terminals {
  if (_terminals is EqualUnmodifiableListView) return _terminals;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_terminals);
}

 final  List<TimelinePatchDocument> _diffs;
@JsonKey() List<TimelinePatchDocument> get diffs {
  if (_diffs is EqualUnmodifiableListView) return _diffs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_diffs);
}

 final  List<AcpContentBlockPresentation> _contentBlocks;
@JsonKey() List<AcpContentBlockPresentation> get contentBlocks {
  if (_contentBlocks is EqualUnmodifiableListView) return _contentBlocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_contentBlocks);
}


/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpTimelineToolCallItemCopyWith<AcpTimelineToolCallItem> get copyWith => _$AcpTimelineToolCallItemCopyWithImpl<AcpTimelineToolCallItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpTimelineToolCallItem&&(identical(other.id, id) || other.id == id)&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId)&&(identical(other.tool, tool) || other.tool == tool)&&(identical(other.status, status) || other.status == status)&&(identical(other.kindLabel, kindLabel) || other.kindLabel == kindLabel)&&const DeepCollectionEquality().equals(other.locations, _locations)&&const DeepCollectionEquality().equals(other.terminals, _terminals)&&const DeepCollectionEquality().equals(other.diffs, _diffs)&&const DeepCollectionEquality().equals(other.contentBlocks, _contentBlocks));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,toolCallId,tool,status,kindLabel,const DeepCollectionEquality().hash(_locations),const DeepCollectionEquality().hash(_terminals),const DeepCollectionEquality().hash(_diffs),const DeepCollectionEquality().hash(_contentBlocks));
}

@override
String toString() {
    return 'AcpTimelineItemPresentation.toolCall(id: $id, toolCallId: $toolCallId, tool: $tool, status: $status, kindLabel: $kindLabel, locations: $locations, terminals: $terminals, diffs: $diffs, contentBlocks: $contentBlocks)';
}


}

/// @nodoc
abstract mixin class $AcpTimelineToolCallItemCopyWith<$Res> implements $AcpTimelineItemPresentationCopyWith<$Res> {
  factory $AcpTimelineToolCallItemCopyWith(AcpTimelineToolCallItem value, $Res Function(AcpTimelineToolCallItem) _then) = _$AcpTimelineToolCallItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String toolCallId, TimelineToolPresentation tool, AcpToolStatusKind status, String? kindLabel, List<String> locations, List<String> terminals, List<TimelinePatchDocument> diffs, List<AcpContentBlockPresentation> contentBlocks
});




}
/// @nodoc
class _$AcpTimelineToolCallItemCopyWithImpl<$Res>
    implements $AcpTimelineToolCallItemCopyWith<$Res> {
  _$AcpTimelineToolCallItemCopyWithImpl(this._self, this._then);

  final AcpTimelineToolCallItem _self;
  final $Res Function(AcpTimelineToolCallItem) _then;

/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? toolCallId = null,Object? tool = null,Object? status = null,Object? kindLabel = freezed,Object? locations = null,Object? terminals = null,Object? diffs = null,Object? contentBlocks = null,}) {
  return _then(AcpTimelineToolCallItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String,tool: null == tool ? _self.tool : tool // ignore: cast_nullable_to_non_nullable
as TimelineToolPresentation,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as AcpToolStatusKind,kindLabel: freezed == kindLabel ? _self.kindLabel : kindLabel // ignore: cast_nullable_to_non_nullable
as String?,locations: null == locations ? _self._locations : locations // ignore: cast_nullable_to_non_nullable
as List<String>,terminals: null == terminals ? _self._terminals : terminals // ignore: cast_nullable_to_non_nullable
as List<String>,diffs: null == diffs ? _self._diffs : diffs // ignore: cast_nullable_to_non_nullable
as List<TimelinePatchDocument>,contentBlocks: null == contentBlocks ? _self._contentBlocks : contentBlocks // ignore: cast_nullable_to_non_nullable
as List<AcpContentBlockPresentation>,
  ));
}


}

/// @nodoc


class AcpTimelineSessionUpdateItem implements AcpTimelineItemPresentation {
  const AcpTimelineSessionUpdateItem({required this.id, required this.update});


@override final  String id;
 final  AcpUpdatePresentation update;

/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpTimelineSessionUpdateItemCopyWith<AcpTimelineSessionUpdateItem> get copyWith => _$AcpTimelineSessionUpdateItemCopyWithImpl<AcpTimelineSessionUpdateItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpTimelineSessionUpdateItem&&(identical(other.id, id) || other.id == id)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,update);
}

@override
String toString() {
    return 'AcpTimelineItemPresentation.sessionUpdate(id: $id, update: $update)';
}


}

/// @nodoc
abstract mixin class $AcpTimelineSessionUpdateItemCopyWith<$Res> implements $AcpTimelineItemPresentationCopyWith<$Res> {
  factory $AcpTimelineSessionUpdateItemCopyWith(AcpTimelineSessionUpdateItem value, $Res Function(AcpTimelineSessionUpdateItem) _then) = _$AcpTimelineSessionUpdateItemCopyWithImpl;
@override @useResult
$Res call({
 String id, AcpUpdatePresentation update
});


$AcpUpdatePresentationCopyWith<$Res> get update;

}
/// @nodoc
class _$AcpTimelineSessionUpdateItemCopyWithImpl<$Res>
    implements $AcpTimelineSessionUpdateItemCopyWith<$Res> {
  _$AcpTimelineSessionUpdateItemCopyWithImpl(this._self, this._then);

  final AcpTimelineSessionUpdateItem _self;
  final $Res Function(AcpTimelineSessionUpdateItem) _then;

/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? update = null,}) {
  return _then(AcpTimelineSessionUpdateItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as AcpUpdatePresentation,
  ));
}

/// Create a copy of AcpTimelineItemPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpUpdatePresentationCopyWith<$Res> get update {

  return $AcpUpdatePresentationCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc
mixin _$AcpPlanEntryPresentation {

 String get content; AcpPlanPriorityKind get priority; AcpPlanStatusKind get status;
/// Create a copy of AcpPlanEntryPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpPlanEntryPresentationCopyWith<AcpPlanEntryPresentation> get copyWith => _$AcpPlanEntryPresentationCopyWithImpl<AcpPlanEntryPresentation>(this as AcpPlanEntryPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpPlanEntryPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpPlanEntryPresentation&&(identical(other.content, _this.content) || other.content == _this.content)&&(identical(other.priority, _this.priority) || other.priority == _this.priority)&&(identical(other.status, _this.status) || other.status == _this.status));
}


@override
int get hashCode {
  final _this = this as AcpPlanEntryPresentation;
  return Object.hash(runtimeType,_this.content,_this.priority,_this.status);
}

@override
String toString() {
  final _this = this as AcpPlanEntryPresentation;
  return 'AcpPlanEntryPresentation(content: ${_this.content}, priority: ${_this.priority}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $AcpPlanEntryPresentationCopyWith<$Res>  {
  factory $AcpPlanEntryPresentationCopyWith(AcpPlanEntryPresentation value, $Res Function(AcpPlanEntryPresentation) _then) = _$AcpPlanEntryPresentationCopyWithImpl;
@useResult
$Res call({
 String content, AcpPlanPriorityKind priority, AcpPlanStatusKind status
});




}
/// @nodoc
class _$AcpPlanEntryPresentationCopyWithImpl<$Res>
    implements $AcpPlanEntryPresentationCopyWith<$Res> {
  _$AcpPlanEntryPresentationCopyWithImpl(this._self, this._then);

  final AcpPlanEntryPresentation _self;
  final $Res Function(AcpPlanEntryPresentation) _then;

/// Create a copy of AcpPlanEntryPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? content = null,Object? priority = null,Object? status = null,}) {
  return _then(AcpPlanEntryPresentation(
content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as AcpPlanPriorityKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as AcpPlanStatusKind,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpPlanEntryPresentation].
extension AcpPlanEntryPresentationPatterns on AcpPlanEntryPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpPlanEntryPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpPlanEntryPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpPlanEntryPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpPlanEntryPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpPlanEntryPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpPlanEntryPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String content,  AcpPlanPriorityKind priority,  AcpPlanStatusKind status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpPlanEntryPresentation() when $default != null:
return $default(_that.content,_that.priority,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String content,  AcpPlanPriorityKind priority,  AcpPlanStatusKind status)  $default,) {final _that = this;
switch (_that) {
case _AcpPlanEntryPresentation():
return $default(_that.content,_that.priority,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String content,  AcpPlanPriorityKind priority,  AcpPlanStatusKind status)?  $default,) {final _that = this;
switch (_that) {
case _AcpPlanEntryPresentation() when $default != null:
return $default(_that.content,_that.priority,_that.status);case _:
  return null;

}
}

}

/// @nodoc


class _AcpPlanEntryPresentation implements AcpPlanEntryPresentation {
  const _AcpPlanEntryPresentation({required this.content, required this.priority, required this.status});


@override final  String content;
@override final  AcpPlanPriorityKind priority;
@override final  AcpPlanStatusKind status;

/// Create a copy of AcpPlanEntryPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpPlanEntryPresentationCopyWith<_AcpPlanEntryPresentation> get copyWith => __$AcpPlanEntryPresentationCopyWithImpl<_AcpPlanEntryPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpPlanEntryPresentation&&(identical(other.content, content) || other.content == content)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,content,priority,status);
}

@override
String toString() {
    return 'AcpPlanEntryPresentation(content: $content, priority: $priority, status: $status)';
}


}

/// @nodoc
abstract mixin class _$AcpPlanEntryPresentationCopyWith<$Res> implements $AcpPlanEntryPresentationCopyWith<$Res> {
  factory _$AcpPlanEntryPresentationCopyWith(_AcpPlanEntryPresentation value, $Res Function(_AcpPlanEntryPresentation) _then) = __$AcpPlanEntryPresentationCopyWithImpl;
@override @useResult
$Res call({
 String content, AcpPlanPriorityKind priority, AcpPlanStatusKind status
});




}
/// @nodoc
class __$AcpPlanEntryPresentationCopyWithImpl<$Res>
    implements _$AcpPlanEntryPresentationCopyWith<$Res> {
  __$AcpPlanEntryPresentationCopyWithImpl(this._self, this._then);

  final _AcpPlanEntryPresentation _self;
  final $Res Function(_AcpPlanEntryPresentation) _then;

/// Create a copy of AcpPlanEntryPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? content = null,Object? priority = null,Object? status = null,}) {
  return _then(_AcpPlanEntryPresentation(
content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as AcpPlanPriorityKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as AcpPlanStatusKind,
  ));
}


}

/// @nodoc
mixin _$AcpPlanCardViewState {

 List<AcpPlanEntryPresentation> get entries; int get completedCount;
/// Create a copy of AcpPlanCardViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpPlanCardViewStateCopyWith<AcpPlanCardViewState> get copyWith => _$AcpPlanCardViewStateCopyWithImpl<AcpPlanCardViewState>(this as AcpPlanCardViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpPlanCardViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpPlanCardViewState&&const DeepCollectionEquality().equals(other.entries, _this.entries)&&(identical(other.completedCount, _this.completedCount) || other.completedCount == _this.completedCount));
}


@override
int get hashCode {
  final _this = this as AcpPlanCardViewState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.entries),_this.completedCount);
}

@override
String toString() {
  final _this = this as AcpPlanCardViewState;
  return 'AcpPlanCardViewState(entries: ${_this.entries}, completedCount: ${_this.completedCount})';
}


}

/// @nodoc
abstract mixin class $AcpPlanCardViewStateCopyWith<$Res>  {
  factory $AcpPlanCardViewStateCopyWith(AcpPlanCardViewState value, $Res Function(AcpPlanCardViewState) _then) = _$AcpPlanCardViewStateCopyWithImpl;
@useResult
$Res call({
 List<AcpPlanEntryPresentation> entries, int completedCount
});




}
/// @nodoc
class _$AcpPlanCardViewStateCopyWithImpl<$Res>
    implements $AcpPlanCardViewStateCopyWith<$Res> {
  _$AcpPlanCardViewStateCopyWithImpl(this._self, this._then);

  final AcpPlanCardViewState _self;
  final $Res Function(AcpPlanCardViewState) _then;

/// Create a copy of AcpPlanCardViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entries = null,Object? completedCount = null,}) {
  return _then(AcpPlanCardViewState(
entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<AcpPlanEntryPresentation>,completedCount: null == completedCount ? _self.completedCount : completedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpPlanCardViewState].
extension AcpPlanCardViewStatePatterns on AcpPlanCardViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpPlanCardViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpPlanCardViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpPlanCardViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpPlanCardViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpPlanCardViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpPlanCardViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<AcpPlanEntryPresentation> entries,  int completedCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpPlanCardViewState() when $default != null:
return $default(_that.entries,_that.completedCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<AcpPlanEntryPresentation> entries,  int completedCount)  $default,) {final _that = this;
switch (_that) {
case _AcpPlanCardViewState():
return $default(_that.entries,_that.completedCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<AcpPlanEntryPresentation> entries,  int completedCount)?  $default,) {final _that = this;
switch (_that) {
case _AcpPlanCardViewState() when $default != null:
return $default(_that.entries,_that.completedCount);case _:
  return null;

}
}

}

/// @nodoc


class _AcpPlanCardViewState implements AcpPlanCardViewState {
  const _AcpPlanCardViewState({required  List<AcpPlanEntryPresentation> entries, required this.completedCount}): _entries = entries;


 final  List<AcpPlanEntryPresentation> _entries;
@override List<AcpPlanEntryPresentation> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}

@override final  int completedCount;

/// Create a copy of AcpPlanCardViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpPlanCardViewStateCopyWith<_AcpPlanCardViewState> get copyWith => __$AcpPlanCardViewStateCopyWithImpl<_AcpPlanCardViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpPlanCardViewState&&const DeepCollectionEquality().equals(other.entries, _entries)&&(identical(other.completedCount, completedCount) || other.completedCount == completedCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_entries),completedCount);
}

@override
String toString() {
    return 'AcpPlanCardViewState(entries: $entries, completedCount: $completedCount)';
}


}

/// @nodoc
abstract mixin class _$AcpPlanCardViewStateCopyWith<$Res> implements $AcpPlanCardViewStateCopyWith<$Res> {
  factory _$AcpPlanCardViewStateCopyWith(_AcpPlanCardViewState value, $Res Function(_AcpPlanCardViewState) _then) = __$AcpPlanCardViewStateCopyWithImpl;
@override @useResult
$Res call({
 List<AcpPlanEntryPresentation> entries, int completedCount
});




}
/// @nodoc
class __$AcpPlanCardViewStateCopyWithImpl<$Res>
    implements _$AcpPlanCardViewStateCopyWith<$Res> {
  __$AcpPlanCardViewStateCopyWithImpl(this._self, this._then);

  final _AcpPlanCardViewState _self;
  final $Res Function(_AcpPlanCardViewState) _then;

/// Create a copy of AcpPlanCardViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entries = null,Object? completedCount = null,}) {
  return _then(_AcpPlanCardViewState(
entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<AcpPlanEntryPresentation>,completedCount: null == completedCount ? _self.completedCount : completedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AcpPermissionOptionPresentation {

 String get optionId; String get name; AcpPermissionOptionTone get tone;
/// Create a copy of AcpPermissionOptionPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpPermissionOptionPresentationCopyWith<AcpPermissionOptionPresentation> get copyWith => _$AcpPermissionOptionPresentationCopyWithImpl<AcpPermissionOptionPresentation>(this as AcpPermissionOptionPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpPermissionOptionPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpPermissionOptionPresentation&&(identical(other.optionId, _this.optionId) || other.optionId == _this.optionId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.tone, _this.tone) || other.tone == _this.tone));
}


@override
int get hashCode {
  final _this = this as AcpPermissionOptionPresentation;
  return Object.hash(runtimeType,_this.optionId,_this.name,_this.tone);
}

@override
String toString() {
  final _this = this as AcpPermissionOptionPresentation;
  return 'AcpPermissionOptionPresentation(optionId: ${_this.optionId}, name: ${_this.name}, tone: ${_this.tone})';
}


}

/// @nodoc
abstract mixin class $AcpPermissionOptionPresentationCopyWith<$Res>  {
  factory $AcpPermissionOptionPresentationCopyWith(AcpPermissionOptionPresentation value, $Res Function(AcpPermissionOptionPresentation) _then) = _$AcpPermissionOptionPresentationCopyWithImpl;
@useResult
$Res call({
 String optionId, String name, AcpPermissionOptionTone tone
});




}
/// @nodoc
class _$AcpPermissionOptionPresentationCopyWithImpl<$Res>
    implements $AcpPermissionOptionPresentationCopyWith<$Res> {
  _$AcpPermissionOptionPresentationCopyWithImpl(this._self, this._then);

  final AcpPermissionOptionPresentation _self;
  final $Res Function(AcpPermissionOptionPresentation) _then;

/// Create a copy of AcpPermissionOptionPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? optionId = null,Object? name = null,Object? tone = null,}) {
  return _then(AcpPermissionOptionPresentation(
optionId: null == optionId ? _self.optionId : optionId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,tone: null == tone ? _self.tone : tone // ignore: cast_nullable_to_non_nullable
as AcpPermissionOptionTone,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpPermissionOptionPresentation].
extension AcpPermissionOptionPresentationPatterns on AcpPermissionOptionPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpPermissionOptionPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpPermissionOptionPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpPermissionOptionPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpPermissionOptionPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpPermissionOptionPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpPermissionOptionPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String optionId,  String name,  AcpPermissionOptionTone tone)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpPermissionOptionPresentation() when $default != null:
return $default(_that.optionId,_that.name,_that.tone);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String optionId,  String name,  AcpPermissionOptionTone tone)  $default,) {final _that = this;
switch (_that) {
case _AcpPermissionOptionPresentation():
return $default(_that.optionId,_that.name,_that.tone);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String optionId,  String name,  AcpPermissionOptionTone tone)?  $default,) {final _that = this;
switch (_that) {
case _AcpPermissionOptionPresentation() when $default != null:
return $default(_that.optionId,_that.name,_that.tone);case _:
  return null;

}
}

}

/// @nodoc


class _AcpPermissionOptionPresentation implements AcpPermissionOptionPresentation {
  const _AcpPermissionOptionPresentation({required this.optionId, required this.name, required this.tone});


@override final  String optionId;
@override final  String name;
@override final  AcpPermissionOptionTone tone;

/// Create a copy of AcpPermissionOptionPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpPermissionOptionPresentationCopyWith<_AcpPermissionOptionPresentation> get copyWith => __$AcpPermissionOptionPresentationCopyWithImpl<_AcpPermissionOptionPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpPermissionOptionPresentation&&(identical(other.optionId, optionId) || other.optionId == optionId)&&(identical(other.name, name) || other.name == name)&&(identical(other.tone, tone) || other.tone == tone));
}


@override
int get hashCode {
    return Object.hash(runtimeType,optionId,name,tone);
}

@override
String toString() {
    return 'AcpPermissionOptionPresentation(optionId: $optionId, name: $name, tone: $tone)';
}


}

/// @nodoc
abstract mixin class _$AcpPermissionOptionPresentationCopyWith<$Res> implements $AcpPermissionOptionPresentationCopyWith<$Res> {
  factory _$AcpPermissionOptionPresentationCopyWith(_AcpPermissionOptionPresentation value, $Res Function(_AcpPermissionOptionPresentation) _then) = __$AcpPermissionOptionPresentationCopyWithImpl;
@override @useResult
$Res call({
 String optionId, String name, AcpPermissionOptionTone tone
});




}
/// @nodoc
class __$AcpPermissionOptionPresentationCopyWithImpl<$Res>
    implements _$AcpPermissionOptionPresentationCopyWith<$Res> {
  __$AcpPermissionOptionPresentationCopyWithImpl(this._self, this._then);

  final _AcpPermissionOptionPresentation _self;
  final $Res Function(_AcpPermissionOptionPresentation) _then;

/// Create a copy of AcpPermissionOptionPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? optionId = null,Object? name = null,Object? tone = null,}) {
  return _then(_AcpPermissionOptionPresentation(
optionId: null == optionId ? _self.optionId : optionId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,tone: null == tone ? _self.tone : tone // ignore: cast_nullable_to_non_nullable
as AcpPermissionOptionTone,
  ));
}


}

/// @nodoc
mixin _$AcpPermissionRequestPresentation {

 String get id; String get title; String? get kindLabel; List<String> get locations; String? get argumentsPreview; List<TimelinePatchDocument> get diffs; List<AcpPermissionOptionPresentation> get options; bool get submitting;
/// Create a copy of AcpPermissionRequestPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpPermissionRequestPresentationCopyWith<AcpPermissionRequestPresentation> get copyWith => _$AcpPermissionRequestPresentationCopyWithImpl<AcpPermissionRequestPresentation>(this as AcpPermissionRequestPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpPermissionRequestPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpPermissionRequestPresentation&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.kindLabel, _this.kindLabel) || other.kindLabel == _this.kindLabel)&&const DeepCollectionEquality().equals(other.locations, _this.locations)&&(identical(other.argumentsPreview, _this.argumentsPreview) || other.argumentsPreview == _this.argumentsPreview)&&const DeepCollectionEquality().equals(other.diffs, _this.diffs)&&const DeepCollectionEquality().equals(other.options, _this.options)&&(identical(other.submitting, _this.submitting) || other.submitting == _this.submitting));
}


@override
int get hashCode {
  final _this = this as AcpPermissionRequestPresentation;
  return Object.hash(runtimeType,_this.id,_this.title,_this.kindLabel,const DeepCollectionEquality().hash(_this.locations),_this.argumentsPreview,const DeepCollectionEquality().hash(_this.diffs),const DeepCollectionEquality().hash(_this.options),_this.submitting);
}

@override
String toString() {
  final _this = this as AcpPermissionRequestPresentation;
  return 'AcpPermissionRequestPresentation(id: ${_this.id}, title: ${_this.title}, kindLabel: ${_this.kindLabel}, locations: ${_this.locations}, argumentsPreview: ${_this.argumentsPreview}, diffs: ${_this.diffs}, options: ${_this.options}, submitting: ${_this.submitting})';
}


}

/// @nodoc
abstract mixin class $AcpPermissionRequestPresentationCopyWith<$Res>  {
  factory $AcpPermissionRequestPresentationCopyWith(AcpPermissionRequestPresentation value, $Res Function(AcpPermissionRequestPresentation) _then) = _$AcpPermissionRequestPresentationCopyWithImpl;
@useResult
$Res call({
 String id, String title, String? kindLabel, List<String> locations, String? argumentsPreview, List<TimelinePatchDocument> diffs, List<AcpPermissionOptionPresentation> options, bool submitting
});




}
/// @nodoc
class _$AcpPermissionRequestPresentationCopyWithImpl<$Res>
    implements $AcpPermissionRequestPresentationCopyWith<$Res> {
  _$AcpPermissionRequestPresentationCopyWithImpl(this._self, this._then);

  final AcpPermissionRequestPresentation _self;
  final $Res Function(AcpPermissionRequestPresentation) _then;

/// Create a copy of AcpPermissionRequestPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? kindLabel = freezed,Object? locations = null,Object? argumentsPreview = freezed,Object? diffs = null,Object? options = null,Object? submitting = null,}) {
  return _then(AcpPermissionRequestPresentation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,kindLabel: freezed == kindLabel ? _self.kindLabel : kindLabel // ignore: cast_nullable_to_non_nullable
as String?,locations: null == locations ? _self.locations : locations // ignore: cast_nullable_to_non_nullable
as List<String>,argumentsPreview: freezed == argumentsPreview ? _self.argumentsPreview : argumentsPreview // ignore: cast_nullable_to_non_nullable
as String?,diffs: null == diffs ? _self.diffs : diffs // ignore: cast_nullable_to_non_nullable
as List<TimelinePatchDocument>,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<AcpPermissionOptionPresentation>,submitting: null == submitting ? _self.submitting : submitting // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpPermissionRequestPresentation].
extension AcpPermissionRequestPresentationPatterns on AcpPermissionRequestPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpPermissionRequestPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpPermissionRequestPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpPermissionRequestPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpPermissionRequestPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpPermissionRequestPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpPermissionRequestPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String? kindLabel,  List<String> locations,  String? argumentsPreview,  List<TimelinePatchDocument> diffs,  List<AcpPermissionOptionPresentation> options,  bool submitting)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpPermissionRequestPresentation() when $default != null:
return $default(_that.id,_that.title,_that.kindLabel,_that.locations,_that.argumentsPreview,_that.diffs,_that.options,_that.submitting);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String? kindLabel,  List<String> locations,  String? argumentsPreview,  List<TimelinePatchDocument> diffs,  List<AcpPermissionOptionPresentation> options,  bool submitting)  $default,) {final _that = this;
switch (_that) {
case _AcpPermissionRequestPresentation():
return $default(_that.id,_that.title,_that.kindLabel,_that.locations,_that.argumentsPreview,_that.diffs,_that.options,_that.submitting);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String? kindLabel,  List<String> locations,  String? argumentsPreview,  List<TimelinePatchDocument> diffs,  List<AcpPermissionOptionPresentation> options,  bool submitting)?  $default,) {final _that = this;
switch (_that) {
case _AcpPermissionRequestPresentation() when $default != null:
return $default(_that.id,_that.title,_that.kindLabel,_that.locations,_that.argumentsPreview,_that.diffs,_that.options,_that.submitting);case _:
  return null;

}
}

}

/// @nodoc


class _AcpPermissionRequestPresentation implements AcpPermissionRequestPresentation {
  const _AcpPermissionRequestPresentation({required this.id, required this.title, this.kindLabel,  List<String> locations = const <String>[], this.argumentsPreview,  List<TimelinePatchDocument> diffs = const <TimelinePatchDocument>[], required  List<AcpPermissionOptionPresentation> options, this.submitting = false}): _locations = locations,_diffs = diffs,_options = options;


@override final  String id;
@override final  String title;
@override final  String? kindLabel;
 final  List<String> _locations;
@override@JsonKey() List<String> get locations {
  if (_locations is EqualUnmodifiableListView) return _locations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_locations);
}

@override final  String? argumentsPreview;
 final  List<TimelinePatchDocument> _diffs;
@override@JsonKey() List<TimelinePatchDocument> get diffs {
  if (_diffs is EqualUnmodifiableListView) return _diffs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_diffs);
}

 final  List<AcpPermissionOptionPresentation> _options;
@override List<AcpPermissionOptionPresentation> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

@override@JsonKey() final  bool submitting;

/// Create a copy of AcpPermissionRequestPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpPermissionRequestPresentationCopyWith<_AcpPermissionRequestPresentation> get copyWith => __$AcpPermissionRequestPresentationCopyWithImpl<_AcpPermissionRequestPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpPermissionRequestPresentation&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.kindLabel, kindLabel) || other.kindLabel == kindLabel)&&const DeepCollectionEquality().equals(other.locations, _locations)&&(identical(other.argumentsPreview, argumentsPreview) || other.argumentsPreview == argumentsPreview)&&const DeepCollectionEquality().equals(other.diffs, _diffs)&&const DeepCollectionEquality().equals(other.options, _options)&&(identical(other.submitting, submitting) || other.submitting == submitting));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,title,kindLabel,const DeepCollectionEquality().hash(_locations),argumentsPreview,const DeepCollectionEquality().hash(_diffs),const DeepCollectionEquality().hash(_options),submitting);
}

@override
String toString() {
    return 'AcpPermissionRequestPresentation(id: $id, title: $title, kindLabel: $kindLabel, locations: $locations, argumentsPreview: $argumentsPreview, diffs: $diffs, options: $options, submitting: $submitting)';
}


}

/// @nodoc
abstract mixin class _$AcpPermissionRequestPresentationCopyWith<$Res> implements $AcpPermissionRequestPresentationCopyWith<$Res> {
  factory _$AcpPermissionRequestPresentationCopyWith(_AcpPermissionRequestPresentation value, $Res Function(_AcpPermissionRequestPresentation) _then) = __$AcpPermissionRequestPresentationCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String? kindLabel, List<String> locations, String? argumentsPreview, List<TimelinePatchDocument> diffs, List<AcpPermissionOptionPresentation> options, bool submitting
});




}
/// @nodoc
class __$AcpPermissionRequestPresentationCopyWithImpl<$Res>
    implements _$AcpPermissionRequestPresentationCopyWith<$Res> {
  __$AcpPermissionRequestPresentationCopyWithImpl(this._self, this._then);

  final _AcpPermissionRequestPresentation _self;
  final $Res Function(_AcpPermissionRequestPresentation) _then;

/// Create a copy of AcpPermissionRequestPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? kindLabel = freezed,Object? locations = null,Object? argumentsPreview = freezed,Object? diffs = null,Object? options = null,Object? submitting = null,}) {
  return _then(_AcpPermissionRequestPresentation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,kindLabel: freezed == kindLabel ? _self.kindLabel : kindLabel // ignore: cast_nullable_to_non_nullable
as String?,locations: null == locations ? _self._locations : locations // ignore: cast_nullable_to_non_nullable
as List<String>,argumentsPreview: freezed == argumentsPreview ? _self.argumentsPreview : argumentsPreview // ignore: cast_nullable_to_non_nullable
as String?,diffs: null == diffs ? _self._diffs : diffs // ignore: cast_nullable_to_non_nullable
as List<TimelinePatchDocument>,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<AcpPermissionOptionPresentation>,submitting: null == submitting ? _self.submitting : submitting // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$AcpPermissionDockViewState {

 int get pendingCount; AcpPermissionRequestPresentation? get activeRequest; String? get errorMessage;
/// Create a copy of AcpPermissionDockViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpPermissionDockViewStateCopyWith<AcpPermissionDockViewState> get copyWith => _$AcpPermissionDockViewStateCopyWithImpl<AcpPermissionDockViewState>(this as AcpPermissionDockViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpPermissionDockViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpPermissionDockViewState&&(identical(other.pendingCount, _this.pendingCount) || other.pendingCount == _this.pendingCount)&&(identical(other.activeRequest, _this.activeRequest) || other.activeRequest == _this.activeRequest)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}


@override
int get hashCode {
  final _this = this as AcpPermissionDockViewState;
  return Object.hash(runtimeType,_this.pendingCount,_this.activeRequest,_this.errorMessage);
}

@override
String toString() {
  final _this = this as AcpPermissionDockViewState;
  return 'AcpPermissionDockViewState(pendingCount: ${_this.pendingCount}, activeRequest: ${_this.activeRequest}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $AcpPermissionDockViewStateCopyWith<$Res>  {
  factory $AcpPermissionDockViewStateCopyWith(AcpPermissionDockViewState value, $Res Function(AcpPermissionDockViewState) _then) = _$AcpPermissionDockViewStateCopyWithImpl;
@useResult
$Res call({
 int pendingCount, AcpPermissionRequestPresentation? activeRequest, String? errorMessage
});


$AcpPermissionRequestPresentationCopyWith<$Res>? get activeRequest;

}
/// @nodoc
class _$AcpPermissionDockViewStateCopyWithImpl<$Res>
    implements $AcpPermissionDockViewStateCopyWith<$Res> {
  _$AcpPermissionDockViewStateCopyWithImpl(this._self, this._then);

  final AcpPermissionDockViewState _self;
  final $Res Function(AcpPermissionDockViewState) _then;

/// Create a copy of AcpPermissionDockViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pendingCount = null,Object? activeRequest = freezed,Object? errorMessage = freezed,}) {
  return _then(AcpPermissionDockViewState(
pendingCount: null == pendingCount ? _self.pendingCount : pendingCount // ignore: cast_nullable_to_non_nullable
as int,activeRequest: freezed == activeRequest ? _self.activeRequest : activeRequest // ignore: cast_nullable_to_non_nullable
as AcpPermissionRequestPresentation?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of AcpPermissionDockViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpPermissionRequestPresentationCopyWith<$Res>? get activeRequest {
    if (_self.activeRequest == null) {
    return null;
  }

  return $AcpPermissionRequestPresentationCopyWith<$Res>(_self.activeRequest!, (value) {
    return _then(_self.copyWith(activeRequest: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpPermissionDockViewState].
extension AcpPermissionDockViewStatePatterns on AcpPermissionDockViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpPermissionDockViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpPermissionDockViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpPermissionDockViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpPermissionDockViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpPermissionDockViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpPermissionDockViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int pendingCount,  AcpPermissionRequestPresentation? activeRequest,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpPermissionDockViewState() when $default != null:
return $default(_that.pendingCount,_that.activeRequest,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int pendingCount,  AcpPermissionRequestPresentation? activeRequest,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _AcpPermissionDockViewState():
return $default(_that.pendingCount,_that.activeRequest,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int pendingCount,  AcpPermissionRequestPresentation? activeRequest,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _AcpPermissionDockViewState() when $default != null:
return $default(_that.pendingCount,_that.activeRequest,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _AcpPermissionDockViewState implements AcpPermissionDockViewState {
  const _AcpPermissionDockViewState({this.pendingCount = 0, this.activeRequest, this.errorMessage});


@override@JsonKey() final  int pendingCount;
@override final  AcpPermissionRequestPresentation? activeRequest;
@override final  String? errorMessage;

/// Create a copy of AcpPermissionDockViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpPermissionDockViewStateCopyWith<_AcpPermissionDockViewState> get copyWith => __$AcpPermissionDockViewStateCopyWithImpl<_AcpPermissionDockViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpPermissionDockViewState&&(identical(other.pendingCount, pendingCount) || other.pendingCount == pendingCount)&&(identical(other.activeRequest, activeRequest) || other.activeRequest == activeRequest)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCount,activeRequest,errorMessage);
}

@override
String toString() {
    return 'AcpPermissionDockViewState(pendingCount: $pendingCount, activeRequest: $activeRequest, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$AcpPermissionDockViewStateCopyWith<$Res> implements $AcpPermissionDockViewStateCopyWith<$Res> {
  factory _$AcpPermissionDockViewStateCopyWith(_AcpPermissionDockViewState value, $Res Function(_AcpPermissionDockViewState) _then) = __$AcpPermissionDockViewStateCopyWithImpl;
@override @useResult
$Res call({
 int pendingCount, AcpPermissionRequestPresentation? activeRequest, String? errorMessage
});


@override $AcpPermissionRequestPresentationCopyWith<$Res>? get activeRequest;

}
/// @nodoc
class __$AcpPermissionDockViewStateCopyWithImpl<$Res>
    implements _$AcpPermissionDockViewStateCopyWith<$Res> {
  __$AcpPermissionDockViewStateCopyWithImpl(this._self, this._then);

  final _AcpPermissionDockViewState _self;
  final $Res Function(_AcpPermissionDockViewState) _then;

/// Create a copy of AcpPermissionDockViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCount = null,Object? activeRequest = freezed,Object? errorMessage = freezed,}) {
  return _then(_AcpPermissionDockViewState(
pendingCount: null == pendingCount ? _self.pendingCount : pendingCount // ignore: cast_nullable_to_non_nullable
as int,activeRequest: freezed == activeRequest ? _self.activeRequest : activeRequest // ignore: cast_nullable_to_non_nullable
as AcpPermissionRequestPresentation?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of AcpPermissionDockViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpPermissionRequestPresentationCopyWith<$Res>? get activeRequest {
    if (_self.activeRequest == null) {
    return null;
  }

  return $AcpPermissionRequestPresentationCopyWith<$Res>(_self.activeRequest!, (value) {
    return _then(_self.copyWith(activeRequest: value));
  });
}
}

/// @nodoc
mixin _$AcpSelectChoicePresentation {

 String get value; String get name; String? get description;
/// Create a copy of AcpSelectChoicePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpSelectChoicePresentationCopyWith<AcpSelectChoicePresentation> get copyWith => _$AcpSelectChoicePresentationCopyWithImpl<AcpSelectChoicePresentation>(this as AcpSelectChoicePresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpSelectChoicePresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpSelectChoicePresentation&&(identical(other.value, _this.value) || other.value == _this.value)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description));
}


@override
int get hashCode {
  final _this = this as AcpSelectChoicePresentation;
  return Object.hash(runtimeType,_this.value,_this.name,_this.description);
}

@override
String toString() {
  final _this = this as AcpSelectChoicePresentation;
  return 'AcpSelectChoicePresentation(value: ${_this.value}, name: ${_this.name}, description: ${_this.description})';
}


}

/// @nodoc
abstract mixin class $AcpSelectChoicePresentationCopyWith<$Res>  {
  factory $AcpSelectChoicePresentationCopyWith(AcpSelectChoicePresentation value, $Res Function(AcpSelectChoicePresentation) _then) = _$AcpSelectChoicePresentationCopyWithImpl;
@useResult
$Res call({
 String value, String name, String? description
});




}
/// @nodoc
class _$AcpSelectChoicePresentationCopyWithImpl<$Res>
    implements $AcpSelectChoicePresentationCopyWith<$Res> {
  _$AcpSelectChoicePresentationCopyWithImpl(this._self, this._then);

  final AcpSelectChoicePresentation _self;
  final $Res Function(AcpSelectChoicePresentation) _then;

/// Create a copy of AcpSelectChoicePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,Object? name = null,Object? description = freezed,}) {
  return _then(AcpSelectChoicePresentation(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpSelectChoicePresentation].
extension AcpSelectChoicePresentationPatterns on AcpSelectChoicePresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpSelectChoicePresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpSelectChoicePresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpSelectChoicePresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpSelectChoicePresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpSelectChoicePresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpSelectChoicePresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String value,  String name,  String? description)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpSelectChoicePresentation() when $default != null:
return $default(_that.value,_that.name,_that.description);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String value,  String name,  String? description)  $default,) {final _that = this;
switch (_that) {
case _AcpSelectChoicePresentation():
return $default(_that.value,_that.name,_that.description);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String value,  String name,  String? description)?  $default,) {final _that = this;
switch (_that) {
case _AcpSelectChoicePresentation() when $default != null:
return $default(_that.value,_that.name,_that.description);case _:
  return null;

}
}

}

/// @nodoc


class _AcpSelectChoicePresentation implements AcpSelectChoicePresentation {
  const _AcpSelectChoicePresentation({required this.value, required this.name, this.description});


@override final  String value;
@override final  String name;
@override final  String? description;

/// Create a copy of AcpSelectChoicePresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpSelectChoicePresentationCopyWith<_AcpSelectChoicePresentation> get copyWith => __$AcpSelectChoicePresentationCopyWithImpl<_AcpSelectChoicePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpSelectChoicePresentation&&(identical(other.value, value) || other.value == value)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value,name,description);
}

@override
String toString() {
    return 'AcpSelectChoicePresentation(value: $value, name: $name, description: $description)';
}


}

/// @nodoc
abstract mixin class _$AcpSelectChoicePresentationCopyWith<$Res> implements $AcpSelectChoicePresentationCopyWith<$Res> {
  factory _$AcpSelectChoicePresentationCopyWith(_AcpSelectChoicePresentation value, $Res Function(_AcpSelectChoicePresentation) _then) = __$AcpSelectChoicePresentationCopyWithImpl;
@override @useResult
$Res call({
 String value, String name, String? description
});




}
/// @nodoc
class __$AcpSelectChoicePresentationCopyWithImpl<$Res>
    implements _$AcpSelectChoicePresentationCopyWith<$Res> {
  __$AcpSelectChoicePresentationCopyWithImpl(this._self, this._then);

  final _AcpSelectChoicePresentation _self;
  final $Res Function(_AcpSelectChoicePresentation) _then;

/// Create a copy of AcpSelectChoicePresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,Object? name = null,Object? description = freezed,}) {
  return _then(_AcpSelectChoicePresentation(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AcpSelectGroupPresentation {

 String get id; String get name; List<AcpSelectChoicePresentation> get options;
/// Create a copy of AcpSelectGroupPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpSelectGroupPresentationCopyWith<AcpSelectGroupPresentation> get copyWith => _$AcpSelectGroupPresentationCopyWithImpl<AcpSelectGroupPresentation>(this as AcpSelectGroupPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpSelectGroupPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpSelectGroupPresentation&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&const DeepCollectionEquality().equals(other.options, _this.options));
}


@override
int get hashCode {
  final _this = this as AcpSelectGroupPresentation;
  return Object.hash(runtimeType,_this.id,_this.name,const DeepCollectionEquality().hash(_this.options));
}

@override
String toString() {
  final _this = this as AcpSelectGroupPresentation;
  return 'AcpSelectGroupPresentation(id: ${_this.id}, name: ${_this.name}, options: ${_this.options})';
}


}

/// @nodoc
abstract mixin class $AcpSelectGroupPresentationCopyWith<$Res>  {
  factory $AcpSelectGroupPresentationCopyWith(AcpSelectGroupPresentation value, $Res Function(AcpSelectGroupPresentation) _then) = _$AcpSelectGroupPresentationCopyWithImpl;
@useResult
$Res call({
 String id, String name, List<AcpSelectChoicePresentation> options
});




}
/// @nodoc
class _$AcpSelectGroupPresentationCopyWithImpl<$Res>
    implements $AcpSelectGroupPresentationCopyWith<$Res> {
  _$AcpSelectGroupPresentationCopyWithImpl(this._self, this._then);

  final AcpSelectGroupPresentation _self;
  final $Res Function(AcpSelectGroupPresentation) _then;

/// Create a copy of AcpSelectGroupPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? options = null,}) {
  return _then(AcpSelectGroupPresentation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<AcpSelectChoicePresentation>,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpSelectGroupPresentation].
extension AcpSelectGroupPresentationPatterns on AcpSelectGroupPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpSelectGroupPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpSelectGroupPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpSelectGroupPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpSelectGroupPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpSelectGroupPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpSelectGroupPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  List<AcpSelectChoicePresentation> options)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpSelectGroupPresentation() when $default != null:
return $default(_that.id,_that.name,_that.options);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  List<AcpSelectChoicePresentation> options)  $default,) {final _that = this;
switch (_that) {
case _AcpSelectGroupPresentation():
return $default(_that.id,_that.name,_that.options);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  List<AcpSelectChoicePresentation> options)?  $default,) {final _that = this;
switch (_that) {
case _AcpSelectGroupPresentation() when $default != null:
return $default(_that.id,_that.name,_that.options);case _:
  return null;

}
}

}

/// @nodoc


class _AcpSelectGroupPresentation implements AcpSelectGroupPresentation {
  const _AcpSelectGroupPresentation({required this.id, required this.name, required  List<AcpSelectChoicePresentation> options}): _options = options;


@override final  String id;
@override final  String name;
 final  List<AcpSelectChoicePresentation> _options;
@override List<AcpSelectChoicePresentation> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}


/// Create a copy of AcpSelectGroupPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpSelectGroupPresentationCopyWith<_AcpSelectGroupPresentation> get copyWith => __$AcpSelectGroupPresentationCopyWithImpl<_AcpSelectGroupPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpSelectGroupPresentation&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.options, _options));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,const DeepCollectionEquality().hash(_options));
}

@override
String toString() {
    return 'AcpSelectGroupPresentation(id: $id, name: $name, options: $options)';
}


}

/// @nodoc
abstract mixin class _$AcpSelectGroupPresentationCopyWith<$Res> implements $AcpSelectGroupPresentationCopyWith<$Res> {
  factory _$AcpSelectGroupPresentationCopyWith(_AcpSelectGroupPresentation value, $Res Function(_AcpSelectGroupPresentation) _then) = __$AcpSelectGroupPresentationCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, List<AcpSelectChoicePresentation> options
});




}
/// @nodoc
class __$AcpSelectGroupPresentationCopyWithImpl<$Res>
    implements _$AcpSelectGroupPresentationCopyWith<$Res> {
  __$AcpSelectGroupPresentationCopyWithImpl(this._self, this._then);

  final _AcpSelectGroupPresentation _self;
  final $Res Function(_AcpSelectGroupPresentation) _then;

/// Create a copy of AcpSelectGroupPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? options = null,}) {
  return _then(_AcpSelectGroupPresentation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<AcpSelectChoicePresentation>,
  ));
}


}

/// @nodoc
mixin _$AcpConfigControlPresentation {

 String get id; String? get description;
/// Create a copy of AcpConfigControlPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpConfigControlPresentationCopyWith<AcpConfigControlPresentation> get copyWith => _$AcpConfigControlPresentationCopyWithImpl<AcpConfigControlPresentation>(this as AcpConfigControlPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpConfigControlPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpConfigControlPresentation&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.description, _this.description) || other.description == _this.description));
}


@override
int get hashCode {
  final _this = this as AcpConfigControlPresentation;
  return Object.hash(runtimeType,_this.id,_this.description);
}

@override
String toString() {
  final _this = this as AcpConfigControlPresentation;
  return 'AcpConfigControlPresentation(id: ${_this.id}, description: ${_this.description})';
}


}

/// @nodoc
abstract mixin class $AcpConfigControlPresentationCopyWith<$Res>  {
  factory $AcpConfigControlPresentationCopyWith(AcpConfigControlPresentation value, $Res Function(AcpConfigControlPresentation) _then) = _$AcpConfigControlPresentationCopyWithImpl;
@useResult
$Res call({
 String id, String? description
});




}
/// @nodoc
class _$AcpConfigControlPresentationCopyWithImpl<$Res>
    implements $AcpConfigControlPresentationCopyWith<$Res> {
  _$AcpConfigControlPresentationCopyWithImpl(this._self, this._then);

  final AcpConfigControlPresentation _self;
  final $Res Function(AcpConfigControlPresentation) _then;

/// Create a copy of AcpConfigControlPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? description = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpConfigControlPresentation].
extension AcpConfigControlPresentationPatterns on AcpConfigControlPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpSelectConfigControl value)?  select,TResult Function( AcpBooleanConfigControl value)?  boolean,TResult Function( AcpLegacyModeConfigControl value)?  legacyMode,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpSelectConfigControl() when select != null:
return select(_that);case AcpBooleanConfigControl() when boolean != null:
return boolean(_that);case AcpLegacyModeConfigControl() when legacyMode != null:
return legacyMode(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpSelectConfigControl value)  select,required TResult Function( AcpBooleanConfigControl value)  boolean,required TResult Function( AcpLegacyModeConfigControl value)  legacyMode,}){
final _that = this;
switch (_that) {
case AcpSelectConfigControl():
return select(_that);case AcpBooleanConfigControl():
return boolean(_that);case AcpLegacyModeConfigControl():
return legacyMode(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpSelectConfigControl value)?  select,TResult? Function( AcpBooleanConfigControl value)?  boolean,TResult? Function( AcpLegacyModeConfigControl value)?  legacyMode,}){
final _that = this;
switch (_that) {
case AcpSelectConfigControl() when select != null:
return select(_that);case AcpBooleanConfigControl() when boolean != null:
return boolean(_that);case AcpLegacyModeConfigControl() when legacyMode != null:
return legacyMode(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String name,  String? description,  AcpConfigCategoryKind category,  String currentValue,  String currentLabel,  List<AcpSelectChoicePresentation> flatOptions,  List<AcpSelectGroupPresentation> groups)?  select,TResult Function( String id,  String name,  String? description,  AcpConfigCategoryKind category,  bool currentValue)?  boolean,TResult Function( String id,  String? description,  String currentModeId,  String currentModeLabel,  List<AcpSelectChoicePresentation> modes)?  legacyMode,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpSelectConfigControl() when select != null:
return select(_that.id,_that.name,_that.description,_that.category,_that.currentValue,_that.currentLabel,_that.flatOptions,_that.groups);case AcpBooleanConfigControl() when boolean != null:
return boolean(_that.id,_that.name,_that.description,_that.category,_that.currentValue);case AcpLegacyModeConfigControl() when legacyMode != null:
return legacyMode(_that.id,_that.description,_that.currentModeId,_that.currentModeLabel,_that.modes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String name,  String? description,  AcpConfigCategoryKind category,  String currentValue,  String currentLabel,  List<AcpSelectChoicePresentation> flatOptions,  List<AcpSelectGroupPresentation> groups)  select,required TResult Function( String id,  String name,  String? description,  AcpConfigCategoryKind category,  bool currentValue)  boolean,required TResult Function( String id,  String? description,  String currentModeId,  String currentModeLabel,  List<AcpSelectChoicePresentation> modes)  legacyMode,}) {final _that = this;
switch (_that) {
case AcpSelectConfigControl():
return select(_that.id,_that.name,_that.description,_that.category,_that.currentValue,_that.currentLabel,_that.flatOptions,_that.groups);case AcpBooleanConfigControl():
return boolean(_that.id,_that.name,_that.description,_that.category,_that.currentValue);case AcpLegacyModeConfigControl():
return legacyMode(_that.id,_that.description,_that.currentModeId,_that.currentModeLabel,_that.modes);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String name,  String? description,  AcpConfigCategoryKind category,  String currentValue,  String currentLabel,  List<AcpSelectChoicePresentation> flatOptions,  List<AcpSelectGroupPresentation> groups)?  select,TResult? Function( String id,  String name,  String? description,  AcpConfigCategoryKind category,  bool currentValue)?  boolean,TResult? Function( String id,  String? description,  String currentModeId,  String currentModeLabel,  List<AcpSelectChoicePresentation> modes)?  legacyMode,}) {final _that = this;
switch (_that) {
case AcpSelectConfigControl() when select != null:
return select(_that.id,_that.name,_that.description,_that.category,_that.currentValue,_that.currentLabel,_that.flatOptions,_that.groups);case AcpBooleanConfigControl() when boolean != null:
return boolean(_that.id,_that.name,_that.description,_that.category,_that.currentValue);case AcpLegacyModeConfigControl() when legacyMode != null:
return legacyMode(_that.id,_that.description,_that.currentModeId,_that.currentModeLabel,_that.modes);case _:
  return null;

}
}

}

/// @nodoc


class AcpSelectConfigControl implements AcpConfigControlPresentation {
  const AcpSelectConfigControl({required this.id, required this.name, this.description, required this.category, required this.currentValue, required this.currentLabel,  List<AcpSelectChoicePresentation> flatOptions = const <AcpSelectChoicePresentation>[],  List<AcpSelectGroupPresentation> groups = const <AcpSelectGroupPresentation>[]}): _flatOptions = flatOptions,_groups = groups;


@override final  String id;
 final  String name;
@override final  String? description;
 final  AcpConfigCategoryKind category;
 final  String currentValue;
 final  String currentLabel;
 final  List<AcpSelectChoicePresentation> _flatOptions;
@JsonKey() List<AcpSelectChoicePresentation> get flatOptions {
  if (_flatOptions is EqualUnmodifiableListView) return _flatOptions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_flatOptions);
}

 final  List<AcpSelectGroupPresentation> _groups;
@JsonKey() List<AcpSelectGroupPresentation> get groups {
  if (_groups is EqualUnmodifiableListView) return _groups;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_groups);
}


/// Create a copy of AcpConfigControlPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpSelectConfigControlCopyWith<AcpSelectConfigControl> get copyWith => _$AcpSelectConfigControlCopyWithImpl<AcpSelectConfigControl>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpSelectConfigControl&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.category, category) || other.category == category)&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue)&&(identical(other.currentLabel, currentLabel) || other.currentLabel == currentLabel)&&const DeepCollectionEquality().equals(other.flatOptions, _flatOptions)&&const DeepCollectionEquality().equals(other.groups, _groups));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,description,category,currentValue,currentLabel,const DeepCollectionEquality().hash(_flatOptions),const DeepCollectionEquality().hash(_groups));
}

@override
String toString() {
    return 'AcpConfigControlPresentation.select(id: $id, name: $name, description: $description, category: $category, currentValue: $currentValue, currentLabel: $currentLabel, flatOptions: $flatOptions, groups: $groups)';
}


}

/// @nodoc
abstract mixin class $AcpSelectConfigControlCopyWith<$Res> implements $AcpConfigControlPresentationCopyWith<$Res> {
  factory $AcpSelectConfigControlCopyWith(AcpSelectConfigControl value, $Res Function(AcpSelectConfigControl) _then) = _$AcpSelectConfigControlCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description, AcpConfigCategoryKind category, String currentValue, String currentLabel, List<AcpSelectChoicePresentation> flatOptions, List<AcpSelectGroupPresentation> groups
});




}
/// @nodoc
class _$AcpSelectConfigControlCopyWithImpl<$Res>
    implements $AcpSelectConfigControlCopyWith<$Res> {
  _$AcpSelectConfigControlCopyWithImpl(this._self, this._then);

  final AcpSelectConfigControl _self;
  final $Res Function(AcpSelectConfigControl) _then;

/// Create a copy of AcpConfigControlPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? category = null,Object? currentValue = null,Object? currentLabel = null,Object? flatOptions = null,Object? groups = null,}) {
  return _then(AcpSelectConfigControl(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as AcpConfigCategoryKind,currentValue: null == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as String,currentLabel: null == currentLabel ? _self.currentLabel : currentLabel // ignore: cast_nullable_to_non_nullable
as String,flatOptions: null == flatOptions ? _self._flatOptions : flatOptions // ignore: cast_nullable_to_non_nullable
as List<AcpSelectChoicePresentation>,groups: null == groups ? _self._groups : groups // ignore: cast_nullable_to_non_nullable
as List<AcpSelectGroupPresentation>,
  ));
}


}

/// @nodoc


class AcpBooleanConfigControl implements AcpConfigControlPresentation {
  const AcpBooleanConfigControl({required this.id, required this.name, this.description, required this.category, required this.currentValue});


@override final  String id;
 final  String name;
@override final  String? description;
 final  AcpConfigCategoryKind category;
 final  bool currentValue;

/// Create a copy of AcpConfigControlPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpBooleanConfigControlCopyWith<AcpBooleanConfigControl> get copyWith => _$AcpBooleanConfigControlCopyWithImpl<AcpBooleanConfigControl>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpBooleanConfigControl&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.category, category) || other.category == category)&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,description,category,currentValue);
}

@override
String toString() {
    return 'AcpConfigControlPresentation.boolean(id: $id, name: $name, description: $description, category: $category, currentValue: $currentValue)';
}


}

/// @nodoc
abstract mixin class $AcpBooleanConfigControlCopyWith<$Res> implements $AcpConfigControlPresentationCopyWith<$Res> {
  factory $AcpBooleanConfigControlCopyWith(AcpBooleanConfigControl value, $Res Function(AcpBooleanConfigControl) _then) = _$AcpBooleanConfigControlCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description, AcpConfigCategoryKind category, bool currentValue
});




}
/// @nodoc
class _$AcpBooleanConfigControlCopyWithImpl<$Res>
    implements $AcpBooleanConfigControlCopyWith<$Res> {
  _$AcpBooleanConfigControlCopyWithImpl(this._self, this._then);

  final AcpBooleanConfigControl _self;
  final $Res Function(AcpBooleanConfigControl) _then;

/// Create a copy of AcpConfigControlPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? category = null,Object? currentValue = null,}) {
  return _then(AcpBooleanConfigControl(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as AcpConfigCategoryKind,currentValue: null == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class AcpLegacyModeConfigControl implements AcpConfigControlPresentation {
  const AcpLegacyModeConfigControl({required this.id, this.description, required this.currentModeId, required this.currentModeLabel, required  List<AcpSelectChoicePresentation> modes}): _modes = modes;


@override final  String id;
@override final  String? description;
 final  String currentModeId;
 final  String currentModeLabel;
 final  List<AcpSelectChoicePresentation> _modes;
 List<AcpSelectChoicePresentation> get modes {
  if (_modes is EqualUnmodifiableListView) return _modes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_modes);
}


/// Create a copy of AcpConfigControlPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpLegacyModeConfigControlCopyWith<AcpLegacyModeConfigControl> get copyWith => _$AcpLegacyModeConfigControlCopyWithImpl<AcpLegacyModeConfigControl>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpLegacyModeConfigControl&&(identical(other.id, id) || other.id == id)&&(identical(other.description, description) || other.description == description)&&(identical(other.currentModeId, currentModeId) || other.currentModeId == currentModeId)&&(identical(other.currentModeLabel, currentModeLabel) || other.currentModeLabel == currentModeLabel)&&const DeepCollectionEquality().equals(other.modes, _modes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,description,currentModeId,currentModeLabel,const DeepCollectionEquality().hash(_modes));
}

@override
String toString() {
    return 'AcpConfigControlPresentation.legacyMode(id: $id, description: $description, currentModeId: $currentModeId, currentModeLabel: $currentModeLabel, modes: $modes)';
}


}

/// @nodoc
abstract mixin class $AcpLegacyModeConfigControlCopyWith<$Res> implements $AcpConfigControlPresentationCopyWith<$Res> {
  factory $AcpLegacyModeConfigControlCopyWith(AcpLegacyModeConfigControl value, $Res Function(AcpLegacyModeConfigControl) _then) = _$AcpLegacyModeConfigControlCopyWithImpl;
@override @useResult
$Res call({
 String id, String? description, String currentModeId, String currentModeLabel, List<AcpSelectChoicePresentation> modes
});




}
/// @nodoc
class _$AcpLegacyModeConfigControlCopyWithImpl<$Res>
    implements $AcpLegacyModeConfigControlCopyWith<$Res> {
  _$AcpLegacyModeConfigControlCopyWithImpl(this._self, this._then);

  final AcpLegacyModeConfigControl _self;
  final $Res Function(AcpLegacyModeConfigControl) _then;

/// Create a copy of AcpConfigControlPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? description = freezed,Object? currentModeId = null,Object? currentModeLabel = null,Object? modes = null,}) {
  return _then(AcpLegacyModeConfigControl(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,currentModeId: null == currentModeId ? _self.currentModeId : currentModeId // ignore: cast_nullable_to_non_nullable
as String,currentModeLabel: null == currentModeLabel ? _self.currentModeLabel : currentModeLabel // ignore: cast_nullable_to_non_nullable
as String,modes: null == modes ? _self._modes : modes // ignore: cast_nullable_to_non_nullable
as List<AcpSelectChoicePresentation>,
  ));
}


}

/// @nodoc
mixin _$AcpConfigurationViewState {

 List<AcpConfigControlPresentation> get controls; bool get pending; bool get enabled; String? get errorMessage;
/// Create a copy of AcpConfigurationViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpConfigurationViewStateCopyWith<AcpConfigurationViewState> get copyWith => _$AcpConfigurationViewStateCopyWithImpl<AcpConfigurationViewState>(this as AcpConfigurationViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpConfigurationViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpConfigurationViewState&&const DeepCollectionEquality().equals(other.controls, _this.controls)&&(identical(other.pending, _this.pending) || other.pending == _this.pending)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}


@override
int get hashCode {
  final _this = this as AcpConfigurationViewState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.controls),_this.pending,_this.enabled,_this.errorMessage);
}

@override
String toString() {
  final _this = this as AcpConfigurationViewState;
  return 'AcpConfigurationViewState(controls: ${_this.controls}, pending: ${_this.pending}, enabled: ${_this.enabled}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $AcpConfigurationViewStateCopyWith<$Res>  {
  factory $AcpConfigurationViewStateCopyWith(AcpConfigurationViewState value, $Res Function(AcpConfigurationViewState) _then) = _$AcpConfigurationViewStateCopyWithImpl;
@useResult
$Res call({
 List<AcpConfigControlPresentation> controls, bool pending, bool enabled, String? errorMessage
});




}
/// @nodoc
class _$AcpConfigurationViewStateCopyWithImpl<$Res>
    implements $AcpConfigurationViewStateCopyWith<$Res> {
  _$AcpConfigurationViewStateCopyWithImpl(this._self, this._then);

  final AcpConfigurationViewState _self;
  final $Res Function(AcpConfigurationViewState) _then;

/// Create a copy of AcpConfigurationViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? controls = null,Object? pending = null,Object? enabled = null,Object? errorMessage = freezed,}) {
  return _then(AcpConfigurationViewState(
controls: null == controls ? _self.controls : controls // ignore: cast_nullable_to_non_nullable
as List<AcpConfigControlPresentation>,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpConfigurationViewState].
extension AcpConfigurationViewStatePatterns on AcpConfigurationViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpConfigurationViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpConfigurationViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpConfigurationViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpConfigurationViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpConfigurationViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpConfigurationViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<AcpConfigControlPresentation> controls,  bool pending,  bool enabled,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpConfigurationViewState() when $default != null:
return $default(_that.controls,_that.pending,_that.enabled,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<AcpConfigControlPresentation> controls,  bool pending,  bool enabled,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _AcpConfigurationViewState():
return $default(_that.controls,_that.pending,_that.enabled,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<AcpConfigControlPresentation> controls,  bool pending,  bool enabled,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _AcpConfigurationViewState() when $default != null:
return $default(_that.controls,_that.pending,_that.enabled,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _AcpConfigurationViewState extends AcpConfigurationViewState {
  const _AcpConfigurationViewState({ List<AcpConfigControlPresentation> controls = const <AcpConfigControlPresentation>[], this.pending = false, this.enabled = false, this.errorMessage}): _controls = controls,super._();


 final  List<AcpConfigControlPresentation> _controls;
@override@JsonKey() List<AcpConfigControlPresentation> get controls {
  if (_controls is EqualUnmodifiableListView) return _controls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_controls);
}

@override@JsonKey() final  bool pending;
@override@JsonKey() final  bool enabled;
@override final  String? errorMessage;

/// Create a copy of AcpConfigurationViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpConfigurationViewStateCopyWith<_AcpConfigurationViewState> get copyWith => __$AcpConfigurationViewStateCopyWithImpl<_AcpConfigurationViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpConfigurationViewState&&const DeepCollectionEquality().equals(other.controls, _controls)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_controls),pending,enabled,errorMessage);
}

@override
String toString() {
    return 'AcpConfigurationViewState(controls: $controls, pending: $pending, enabled: $enabled, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$AcpConfigurationViewStateCopyWith<$Res> implements $AcpConfigurationViewStateCopyWith<$Res> {
  factory _$AcpConfigurationViewStateCopyWith(_AcpConfigurationViewState value, $Res Function(_AcpConfigurationViewState) _then) = __$AcpConfigurationViewStateCopyWithImpl;
@override @useResult
$Res call({
 List<AcpConfigControlPresentation> controls, bool pending, bool enabled, String? errorMessage
});




}
/// @nodoc
class __$AcpConfigurationViewStateCopyWithImpl<$Res>
    implements _$AcpConfigurationViewStateCopyWith<$Res> {
  __$AcpConfigurationViewStateCopyWithImpl(this._self, this._then);

  final _AcpConfigurationViewState _self;
  final $Res Function(_AcpConfigurationViewState) _then;

/// Create a copy of AcpConfigurationViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? controls = null,Object? pending = null,Object? enabled = null,Object? errorMessage = freezed,}) {
  return _then(_AcpConfigurationViewState(
controls: null == controls ? _self._controls : controls // ignore: cast_nullable_to_non_nullable
as List<AcpConfigControlPresentation>,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AcpComposerBlocker {

 AcpComposerBlockerKind get kind; String? get detail;
/// Create a copy of AcpComposerBlocker
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpComposerBlockerCopyWith<AcpComposerBlocker> get copyWith => _$AcpComposerBlockerCopyWithImpl<AcpComposerBlocker>(this as AcpComposerBlocker, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpComposerBlocker;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpComposerBlocker&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as AcpComposerBlocker;
  return Object.hash(runtimeType,_this.kind,_this.detail);
}

@override
String toString() {
  final _this = this as AcpComposerBlocker;
  return 'AcpComposerBlocker(kind: ${_this.kind}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $AcpComposerBlockerCopyWith<$Res>  {
  factory $AcpComposerBlockerCopyWith(AcpComposerBlocker value, $Res Function(AcpComposerBlocker) _then) = _$AcpComposerBlockerCopyWithImpl;
@useResult
$Res call({
 AcpComposerBlockerKind kind, String? detail
});




}
/// @nodoc
class _$AcpComposerBlockerCopyWithImpl<$Res>
    implements $AcpComposerBlockerCopyWith<$Res> {
  _$AcpComposerBlockerCopyWithImpl(this._self, this._then);

  final AcpComposerBlocker _self;
  final $Res Function(AcpComposerBlocker) _then;

/// Create a copy of AcpComposerBlocker
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? detail = freezed,}) {
  return _then(AcpComposerBlocker(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AcpComposerBlockerKind,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpComposerBlocker].
extension AcpComposerBlockerPatterns on AcpComposerBlocker {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpComposerBlocker value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpComposerBlocker() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpComposerBlocker value)  $default,){
final _that = this;
switch (_that) {
case _AcpComposerBlocker():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpComposerBlocker value)?  $default,){
final _that = this;
switch (_that) {
case _AcpComposerBlocker() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpComposerBlockerKind kind,  String? detail)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpComposerBlocker() when $default != null:
return $default(_that.kind,_that.detail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpComposerBlockerKind kind,  String? detail)  $default,) {final _that = this;
switch (_that) {
case _AcpComposerBlocker():
return $default(_that.kind,_that.detail);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpComposerBlockerKind kind,  String? detail)?  $default,) {final _that = this;
switch (_that) {
case _AcpComposerBlocker() when $default != null:
return $default(_that.kind,_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class _AcpComposerBlocker implements AcpComposerBlocker {
  const _AcpComposerBlocker({required this.kind, this.detail});


@override final  AcpComposerBlockerKind kind;
@override final  String? detail;

/// Create a copy of AcpComposerBlocker
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpComposerBlockerCopyWith<_AcpComposerBlocker> get copyWith => __$AcpComposerBlockerCopyWithImpl<_AcpComposerBlocker>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpComposerBlocker&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,detail);
}

@override
String toString() {
    return 'AcpComposerBlocker(kind: $kind, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$AcpComposerBlockerCopyWith<$Res> implements $AcpComposerBlockerCopyWith<$Res> {
  factory _$AcpComposerBlockerCopyWith(_AcpComposerBlocker value, $Res Function(_AcpComposerBlocker) _then) = __$AcpComposerBlockerCopyWithImpl;
@override @useResult
$Res call({
 AcpComposerBlockerKind kind, String? detail
});




}
/// @nodoc
class __$AcpComposerBlockerCopyWithImpl<$Res>
    implements _$AcpComposerBlockerCopyWith<$Res> {
  __$AcpComposerBlockerCopyWithImpl(this._self, this._then);

  final _AcpComposerBlocker _self;
  final $Res Function(_AcpComposerBlocker) _then;

/// Create a copy of AcpComposerBlocker
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? detail = freezed,}) {
  return _then(_AcpComposerBlocker(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AcpComposerBlockerKind,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AcpComposerViewState {

 String get threadId; String get draftText; List<AttachmentDraftView> get attachments; List<ModelInputCapabilityView> get localCapabilities; List<ModelInputCapabilityView> get remoteCapabilities; bool get supportsImagePaste; bool get canSend; bool get isRunning; bool get canInterrupt; bool get canAttach; bool get submitting; AcpComposerBlocker? get blocker; String? get draftError;
/// Create a copy of AcpComposerViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpComposerViewStateCopyWith<AcpComposerViewState> get copyWith => _$AcpComposerViewStateCopyWithImpl<AcpComposerViewState>(this as AcpComposerViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpComposerViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpComposerViewState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.draftText, _this.draftText) || other.draftText == _this.draftText)&&const DeepCollectionEquality().equals(other.attachments, _this.attachments)&&const DeepCollectionEquality().equals(other.localCapabilities, _this.localCapabilities)&&const DeepCollectionEquality().equals(other.remoteCapabilities, _this.remoteCapabilities)&&(identical(other.supportsImagePaste, _this.supportsImagePaste) || other.supportsImagePaste == _this.supportsImagePaste)&&(identical(other.canSend, _this.canSend) || other.canSend == _this.canSend)&&(identical(other.isRunning, _this.isRunning) || other.isRunning == _this.isRunning)&&(identical(other.canInterrupt, _this.canInterrupt) || other.canInterrupt == _this.canInterrupt)&&(identical(other.canAttach, _this.canAttach) || other.canAttach == _this.canAttach)&&(identical(other.submitting, _this.submitting) || other.submitting == _this.submitting)&&(identical(other.blocker, _this.blocker) || other.blocker == _this.blocker)&&(identical(other.draftError, _this.draftError) || other.draftError == _this.draftError));
}


@override
int get hashCode {
  final _this = this as AcpComposerViewState;
  return Object.hash(runtimeType,_this.threadId,_this.draftText,const DeepCollectionEquality().hash(_this.attachments),const DeepCollectionEquality().hash(_this.localCapabilities),const DeepCollectionEquality().hash(_this.remoteCapabilities),_this.supportsImagePaste,_this.canSend,_this.isRunning,_this.canInterrupt,_this.canAttach,_this.submitting,_this.blocker,_this.draftError);
}

@override
String toString() {
  final _this = this as AcpComposerViewState;
  return 'AcpComposerViewState(threadId: ${_this.threadId}, draftText: ${_this.draftText}, attachments: ${_this.attachments}, localCapabilities: ${_this.localCapabilities}, remoteCapabilities: ${_this.remoteCapabilities}, supportsImagePaste: ${_this.supportsImagePaste}, canSend: ${_this.canSend}, isRunning: ${_this.isRunning}, canInterrupt: ${_this.canInterrupt}, canAttach: ${_this.canAttach}, submitting: ${_this.submitting}, blocker: ${_this.blocker}, draftError: ${_this.draftError})';
}


}

/// @nodoc
abstract mixin class $AcpComposerViewStateCopyWith<$Res>  {
  factory $AcpComposerViewStateCopyWith(AcpComposerViewState value, $Res Function(AcpComposerViewState) _then) = _$AcpComposerViewStateCopyWithImpl;
@useResult
$Res call({
 String threadId, String draftText, List<AttachmentDraftView> attachments, List<ModelInputCapabilityView> localCapabilities, List<ModelInputCapabilityView> remoteCapabilities, bool supportsImagePaste, bool canSend, bool isRunning, bool canInterrupt, bool canAttach, bool submitting, AcpComposerBlocker? blocker, String? draftError
});


$AcpComposerBlockerCopyWith<$Res>? get blocker;

}
/// @nodoc
class _$AcpComposerViewStateCopyWithImpl<$Res>
    implements $AcpComposerViewStateCopyWith<$Res> {
  _$AcpComposerViewStateCopyWithImpl(this._self, this._then);

  final AcpComposerViewState _self;
  final $Res Function(AcpComposerViewState) _then;

/// Create a copy of AcpComposerViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? draftText = null,Object? attachments = null,Object? localCapabilities = null,Object? remoteCapabilities = null,Object? supportsImagePaste = null,Object? canSend = null,Object? isRunning = null,Object? canInterrupt = null,Object? canAttach = null,Object? submitting = null,Object? blocker = freezed,Object? draftError = freezed,}) {
  return _then(AcpComposerViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,draftText: null == draftText ? _self.draftText : draftText // ignore: cast_nullable_to_non_nullable
as String,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<AttachmentDraftView>,localCapabilities: null == localCapabilities ? _self.localCapabilities : localCapabilities // ignore: cast_nullable_to_non_nullable
as List<ModelInputCapabilityView>,remoteCapabilities: null == remoteCapabilities ? _self.remoteCapabilities : remoteCapabilities // ignore: cast_nullable_to_non_nullable
as List<ModelInputCapabilityView>,supportsImagePaste: null == supportsImagePaste ? _self.supportsImagePaste : supportsImagePaste // ignore: cast_nullable_to_non_nullable
as bool,canSend: null == canSend ? _self.canSend : canSend // ignore: cast_nullable_to_non_nullable
as bool,isRunning: null == isRunning ? _self.isRunning : isRunning // ignore: cast_nullable_to_non_nullable
as bool,canInterrupt: null == canInterrupt ? _self.canInterrupt : canInterrupt // ignore: cast_nullable_to_non_nullable
as bool,canAttach: null == canAttach ? _self.canAttach : canAttach // ignore: cast_nullable_to_non_nullable
as bool,submitting: null == submitting ? _self.submitting : submitting // ignore: cast_nullable_to_non_nullable
as bool,blocker: freezed == blocker ? _self.blocker : blocker // ignore: cast_nullable_to_non_nullable
as AcpComposerBlocker?,draftError: freezed == draftError ? _self.draftError : draftError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of AcpComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpComposerBlockerCopyWith<$Res>? get blocker {
    if (_self.blocker == null) {
    return null;
  }

  return $AcpComposerBlockerCopyWith<$Res>(_self.blocker!, (value) {
    return _then(_self.copyWith(blocker: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpComposerViewState].
extension AcpComposerViewStatePatterns on AcpComposerViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpComposerViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpComposerViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpComposerViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpComposerViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpComposerViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpComposerViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  String draftText,  List<AttachmentDraftView> attachments,  List<ModelInputCapabilityView> localCapabilities,  List<ModelInputCapabilityView> remoteCapabilities,  bool supportsImagePaste,  bool canSend,  bool isRunning,  bool canInterrupt,  bool canAttach,  bool submitting,  AcpComposerBlocker? blocker,  String? draftError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpComposerViewState() when $default != null:
return $default(_that.threadId,_that.draftText,_that.attachments,_that.localCapabilities,_that.remoteCapabilities,_that.supportsImagePaste,_that.canSend,_that.isRunning,_that.canInterrupt,_that.canAttach,_that.submitting,_that.blocker,_that.draftError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  String draftText,  List<AttachmentDraftView> attachments,  List<ModelInputCapabilityView> localCapabilities,  List<ModelInputCapabilityView> remoteCapabilities,  bool supportsImagePaste,  bool canSend,  bool isRunning,  bool canInterrupt,  bool canAttach,  bool submitting,  AcpComposerBlocker? blocker,  String? draftError)  $default,) {final _that = this;
switch (_that) {
case _AcpComposerViewState():
return $default(_that.threadId,_that.draftText,_that.attachments,_that.localCapabilities,_that.remoteCapabilities,_that.supportsImagePaste,_that.canSend,_that.isRunning,_that.canInterrupt,_that.canAttach,_that.submitting,_that.blocker,_that.draftError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  String draftText,  List<AttachmentDraftView> attachments,  List<ModelInputCapabilityView> localCapabilities,  List<ModelInputCapabilityView> remoteCapabilities,  bool supportsImagePaste,  bool canSend,  bool isRunning,  bool canInterrupt,  bool canAttach,  bool submitting,  AcpComposerBlocker? blocker,  String? draftError)?  $default,) {final _that = this;
switch (_that) {
case _AcpComposerViewState() when $default != null:
return $default(_that.threadId,_that.draftText,_that.attachments,_that.localCapabilities,_that.remoteCapabilities,_that.supportsImagePaste,_that.canSend,_that.isRunning,_that.canInterrupt,_that.canAttach,_that.submitting,_that.blocker,_that.draftError);case _:
  return null;

}
}

}

/// @nodoc


class _AcpComposerViewState extends AcpComposerViewState {
  const _AcpComposerViewState({required this.threadId, this.draftText = '',  List<AttachmentDraftView> attachments = const <AttachmentDraftView>[],  List<ModelInputCapabilityView> localCapabilities = const <ModelInputCapabilityView>[],  List<ModelInputCapabilityView> remoteCapabilities = const <ModelInputCapabilityView>[], this.supportsImagePaste = false, this.canSend = false, this.isRunning = false, this.canInterrupt = false, this.canAttach = false, this.submitting = false, this.blocker, this.draftError}): _attachments = attachments,_localCapabilities = localCapabilities,_remoteCapabilities = remoteCapabilities,super._();


@override final  String threadId;
@override@JsonKey() final  String draftText;
 final  List<AttachmentDraftView> _attachments;
@override@JsonKey() List<AttachmentDraftView> get attachments {
  if (_attachments is EqualUnmodifiableListView) return _attachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attachments);
}

 final  List<ModelInputCapabilityView> _localCapabilities;
@override@JsonKey() List<ModelInputCapabilityView> get localCapabilities {
  if (_localCapabilities is EqualUnmodifiableListView) return _localCapabilities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_localCapabilities);
}

 final  List<ModelInputCapabilityView> _remoteCapabilities;
@override@JsonKey() List<ModelInputCapabilityView> get remoteCapabilities {
  if (_remoteCapabilities is EqualUnmodifiableListView) return _remoteCapabilities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_remoteCapabilities);
}

@override@JsonKey() final  bool supportsImagePaste;
@override@JsonKey() final  bool canSend;
@override@JsonKey() final  bool isRunning;
@override@JsonKey() final  bool canInterrupt;
@override@JsonKey() final  bool canAttach;
@override@JsonKey() final  bool submitting;
@override final  AcpComposerBlocker? blocker;
@override final  String? draftError;

/// Create a copy of AcpComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpComposerViewStateCopyWith<_AcpComposerViewState> get copyWith => __$AcpComposerViewStateCopyWithImpl<_AcpComposerViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpComposerViewState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.draftText, draftText) || other.draftText == draftText)&&const DeepCollectionEquality().equals(other.attachments, _attachments)&&const DeepCollectionEquality().equals(other.localCapabilities, _localCapabilities)&&const DeepCollectionEquality().equals(other.remoteCapabilities, _remoteCapabilities)&&(identical(other.supportsImagePaste, supportsImagePaste) || other.supportsImagePaste == supportsImagePaste)&&(identical(other.canSend, canSend) || other.canSend == canSend)&&(identical(other.isRunning, isRunning) || other.isRunning == isRunning)&&(identical(other.canInterrupt, canInterrupt) || other.canInterrupt == canInterrupt)&&(identical(other.canAttach, canAttach) || other.canAttach == canAttach)&&(identical(other.submitting, submitting) || other.submitting == submitting)&&(identical(other.blocker, blocker) || other.blocker == blocker)&&(identical(other.draftError, draftError) || other.draftError == draftError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,draftText,const DeepCollectionEquality().hash(_attachments),const DeepCollectionEquality().hash(_localCapabilities),const DeepCollectionEquality().hash(_remoteCapabilities),supportsImagePaste,canSend,isRunning,canInterrupt,canAttach,submitting,blocker,draftError);
}

@override
String toString() {
    return 'AcpComposerViewState(threadId: $threadId, draftText: $draftText, attachments: $attachments, localCapabilities: $localCapabilities, remoteCapabilities: $remoteCapabilities, supportsImagePaste: $supportsImagePaste, canSend: $canSend, isRunning: $isRunning, canInterrupt: $canInterrupt, canAttach: $canAttach, submitting: $submitting, blocker: $blocker, draftError: $draftError)';
}


}

/// @nodoc
abstract mixin class _$AcpComposerViewStateCopyWith<$Res> implements $AcpComposerViewStateCopyWith<$Res> {
  factory _$AcpComposerViewStateCopyWith(_AcpComposerViewState value, $Res Function(_AcpComposerViewState) _then) = __$AcpComposerViewStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, String draftText, List<AttachmentDraftView> attachments, List<ModelInputCapabilityView> localCapabilities, List<ModelInputCapabilityView> remoteCapabilities, bool supportsImagePaste, bool canSend, bool isRunning, bool canInterrupt, bool canAttach, bool submitting, AcpComposerBlocker? blocker, String? draftError
});


@override $AcpComposerBlockerCopyWith<$Res>? get blocker;

}
/// @nodoc
class __$AcpComposerViewStateCopyWithImpl<$Res>
    implements _$AcpComposerViewStateCopyWith<$Res> {
  __$AcpComposerViewStateCopyWithImpl(this._self, this._then);

  final _AcpComposerViewState _self;
  final $Res Function(_AcpComposerViewState) _then;

/// Create a copy of AcpComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? draftText = null,Object? attachments = null,Object? localCapabilities = null,Object? remoteCapabilities = null,Object? supportsImagePaste = null,Object? canSend = null,Object? isRunning = null,Object? canInterrupt = null,Object? canAttach = null,Object? submitting = null,Object? blocker = freezed,Object? draftError = freezed,}) {
  return _then(_AcpComposerViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,draftText: null == draftText ? _self.draftText : draftText // ignore: cast_nullable_to_non_nullable
as String,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<AttachmentDraftView>,localCapabilities: null == localCapabilities ? _self._localCapabilities : localCapabilities // ignore: cast_nullable_to_non_nullable
as List<ModelInputCapabilityView>,remoteCapabilities: null == remoteCapabilities ? _self._remoteCapabilities : remoteCapabilities // ignore: cast_nullable_to_non_nullable
as List<ModelInputCapabilityView>,supportsImagePaste: null == supportsImagePaste ? _self.supportsImagePaste : supportsImagePaste // ignore: cast_nullable_to_non_nullable
as bool,canSend: null == canSend ? _self.canSend : canSend // ignore: cast_nullable_to_non_nullable
as bool,isRunning: null == isRunning ? _self.isRunning : isRunning // ignore: cast_nullable_to_non_nullable
as bool,canInterrupt: null == canInterrupt ? _self.canInterrupt : canInterrupt // ignore: cast_nullable_to_non_nullable
as bool,canAttach: null == canAttach ? _self.canAttach : canAttach // ignore: cast_nullable_to_non_nullable
as bool,submitting: null == submitting ? _self.submitting : submitting // ignore: cast_nullable_to_non_nullable
as bool,blocker: freezed == blocker ? _self.blocker : blocker // ignore: cast_nullable_to_non_nullable
as AcpComposerBlocker?,draftError: freezed == draftError ? _self.draftError : draftError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of AcpComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpComposerBlockerCopyWith<$Res>? get blocker {
    if (_self.blocker == null) {
    return null;
  }

  return $AcpComposerBlockerCopyWith<$Res>(_self.blocker!, (value) {
    return _then(_self.copyWith(blocker: value));
  });
}
}

/// @nodoc
mixin _$AcpUsagePresentation {

 String get usedFormatted; String get sizeFormatted; double get ratio; String? get costLabel;
/// Create a copy of AcpUsagePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpUsagePresentationCopyWith<AcpUsagePresentation> get copyWith => _$AcpUsagePresentationCopyWithImpl<AcpUsagePresentation>(this as AcpUsagePresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpUsagePresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpUsagePresentation&&(identical(other.usedFormatted, _this.usedFormatted) || other.usedFormatted == _this.usedFormatted)&&(identical(other.sizeFormatted, _this.sizeFormatted) || other.sizeFormatted == _this.sizeFormatted)&&(identical(other.ratio, _this.ratio) || other.ratio == _this.ratio)&&(identical(other.costLabel, _this.costLabel) || other.costLabel == _this.costLabel));
}


@override
int get hashCode {
  final _this = this as AcpUsagePresentation;
  return Object.hash(runtimeType,_this.usedFormatted,_this.sizeFormatted,_this.ratio,_this.costLabel);
}

@override
String toString() {
  final _this = this as AcpUsagePresentation;
  return 'AcpUsagePresentation(usedFormatted: ${_this.usedFormatted}, sizeFormatted: ${_this.sizeFormatted}, ratio: ${_this.ratio}, costLabel: ${_this.costLabel})';
}


}

/// @nodoc
abstract mixin class $AcpUsagePresentationCopyWith<$Res>  {
  factory $AcpUsagePresentationCopyWith(AcpUsagePresentation value, $Res Function(AcpUsagePresentation) _then) = _$AcpUsagePresentationCopyWithImpl;
@useResult
$Res call({
 String usedFormatted, String sizeFormatted, double ratio, String? costLabel
});




}
/// @nodoc
class _$AcpUsagePresentationCopyWithImpl<$Res>
    implements $AcpUsagePresentationCopyWith<$Res> {
  _$AcpUsagePresentationCopyWithImpl(this._self, this._then);

  final AcpUsagePresentation _self;
  final $Res Function(AcpUsagePresentation) _then;

/// Create a copy of AcpUsagePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? usedFormatted = null,Object? sizeFormatted = null,Object? ratio = null,Object? costLabel = freezed,}) {
  return _then(AcpUsagePresentation(
usedFormatted: null == usedFormatted ? _self.usedFormatted : usedFormatted // ignore: cast_nullable_to_non_nullable
as String,sizeFormatted: null == sizeFormatted ? _self.sizeFormatted : sizeFormatted // ignore: cast_nullable_to_non_nullable
as String,ratio: null == ratio ? _self.ratio : ratio // ignore: cast_nullable_to_non_nullable
as double,costLabel: freezed == costLabel ? _self.costLabel : costLabel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpUsagePresentation].
extension AcpUsagePresentationPatterns on AcpUsagePresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpUsagePresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpUsagePresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpUsagePresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpUsagePresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpUsagePresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpUsagePresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String usedFormatted,  String sizeFormatted,  double ratio,  String? costLabel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpUsagePresentation() when $default != null:
return $default(_that.usedFormatted,_that.sizeFormatted,_that.ratio,_that.costLabel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String usedFormatted,  String sizeFormatted,  double ratio,  String? costLabel)  $default,) {final _that = this;
switch (_that) {
case _AcpUsagePresentation():
return $default(_that.usedFormatted,_that.sizeFormatted,_that.ratio,_that.costLabel);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String usedFormatted,  String sizeFormatted,  double ratio,  String? costLabel)?  $default,) {final _that = this;
switch (_that) {
case _AcpUsagePresentation() when $default != null:
return $default(_that.usedFormatted,_that.sizeFormatted,_that.ratio,_that.costLabel);case _:
  return null;

}
}

}

/// @nodoc


class _AcpUsagePresentation implements AcpUsagePresentation {
  const _AcpUsagePresentation({required this.usedFormatted, required this.sizeFormatted, required this.ratio, this.costLabel});


@override final  String usedFormatted;
@override final  String sizeFormatted;
@override final  double ratio;
@override final  String? costLabel;

/// Create a copy of AcpUsagePresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpUsagePresentationCopyWith<_AcpUsagePresentation> get copyWith => __$AcpUsagePresentationCopyWithImpl<_AcpUsagePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpUsagePresentation&&(identical(other.usedFormatted, usedFormatted) || other.usedFormatted == usedFormatted)&&(identical(other.sizeFormatted, sizeFormatted) || other.sizeFormatted == sizeFormatted)&&(identical(other.ratio, ratio) || other.ratio == ratio)&&(identical(other.costLabel, costLabel) || other.costLabel == costLabel));
}


@override
int get hashCode {
    return Object.hash(runtimeType,usedFormatted,sizeFormatted,ratio,costLabel);
}

@override
String toString() {
    return 'AcpUsagePresentation(usedFormatted: $usedFormatted, sizeFormatted: $sizeFormatted, ratio: $ratio, costLabel: $costLabel)';
}


}

/// @nodoc
abstract mixin class _$AcpUsagePresentationCopyWith<$Res> implements $AcpUsagePresentationCopyWith<$Res> {
  factory _$AcpUsagePresentationCopyWith(_AcpUsagePresentation value, $Res Function(_AcpUsagePresentation) _then) = __$AcpUsagePresentationCopyWithImpl;
@override @useResult
$Res call({
 String usedFormatted, String sizeFormatted, double ratio, String? costLabel
});




}
/// @nodoc
class __$AcpUsagePresentationCopyWithImpl<$Res>
    implements _$AcpUsagePresentationCopyWith<$Res> {
  __$AcpUsagePresentationCopyWithImpl(this._self, this._then);

  final _AcpUsagePresentation _self;
  final $Res Function(_AcpUsagePresentation) _then;

/// Create a copy of AcpUsagePresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? usedFormatted = null,Object? sizeFormatted = null,Object? ratio = null,Object? costLabel = freezed,}) {
  return _then(_AcpUsagePresentation(
usedFormatted: null == usedFormatted ? _self.usedFormatted : usedFormatted // ignore: cast_nullable_to_non_nullable
as String,sizeFormatted: null == sizeFormatted ? _self.sizeFormatted : sizeFormatted // ignore: cast_nullable_to_non_nullable
as String,ratio: null == ratio ? _self.ratio : ratio // ignore: cast_nullable_to_non_nullable
as double,costLabel: freezed == costLabel ? _self.costLabel : costLabel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AcpStatusBarViewState {

 AcpSessionStatusPhase get phase; AcpStopReasonKind? get stopReason; String? get stopReasonRaw; AcpHistoryOriginKind? get provenance; AcpUsagePresentation? get usage;
/// Create a copy of AcpStatusBarViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpStatusBarViewStateCopyWith<AcpStatusBarViewState> get copyWith => _$AcpStatusBarViewStateCopyWithImpl<AcpStatusBarViewState>(this as AcpStatusBarViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpStatusBarViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpStatusBarViewState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.stopReason, _this.stopReason) || other.stopReason == _this.stopReason)&&(identical(other.stopReasonRaw, _this.stopReasonRaw) || other.stopReasonRaw == _this.stopReasonRaw)&&(identical(other.provenance, _this.provenance) || other.provenance == _this.provenance)&&(identical(other.usage, _this.usage) || other.usage == _this.usage));
}


@override
int get hashCode {
  final _this = this as AcpStatusBarViewState;
  return Object.hash(runtimeType,_this.phase,_this.stopReason,_this.stopReasonRaw,_this.provenance,_this.usage);
}

@override
String toString() {
  final _this = this as AcpStatusBarViewState;
  return 'AcpStatusBarViewState(phase: ${_this.phase}, stopReason: ${_this.stopReason}, stopReasonRaw: ${_this.stopReasonRaw}, provenance: ${_this.provenance}, usage: ${_this.usage})';
}


}

/// @nodoc
abstract mixin class $AcpStatusBarViewStateCopyWith<$Res>  {
  factory $AcpStatusBarViewStateCopyWith(AcpStatusBarViewState value, $Res Function(AcpStatusBarViewState) _then) = _$AcpStatusBarViewStateCopyWithImpl;
@useResult
$Res call({
 AcpSessionStatusPhase phase, AcpStopReasonKind? stopReason, String? stopReasonRaw, AcpHistoryOriginKind? provenance, AcpUsagePresentation? usage
});


$AcpUsagePresentationCopyWith<$Res>? get usage;

}
/// @nodoc
class _$AcpStatusBarViewStateCopyWithImpl<$Res>
    implements $AcpStatusBarViewStateCopyWith<$Res> {
  _$AcpStatusBarViewStateCopyWithImpl(this._self, this._then);

  final AcpStatusBarViewState _self;
  final $Res Function(AcpStatusBarViewState) _then;

/// Create a copy of AcpStatusBarViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? stopReason = freezed,Object? stopReasonRaw = freezed,Object? provenance = freezed,Object? usage = freezed,}) {
  return _then(AcpStatusBarViewState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AcpSessionStatusPhase,stopReason: freezed == stopReason ? _self.stopReason : stopReason // ignore: cast_nullable_to_non_nullable
as AcpStopReasonKind?,stopReasonRaw: freezed == stopReasonRaw ? _self.stopReasonRaw : stopReasonRaw // ignore: cast_nullable_to_non_nullable
as String?,provenance: freezed == provenance ? _self.provenance : provenance // ignore: cast_nullable_to_non_nullable
as AcpHistoryOriginKind?,usage: freezed == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as AcpUsagePresentation?,
  ));
}
/// Create a copy of AcpStatusBarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpUsagePresentationCopyWith<$Res>? get usage {
    if (_self.usage == null) {
    return null;
  }

  return $AcpUsagePresentationCopyWith<$Res>(_self.usage!, (value) {
    return _then(_self.copyWith(usage: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpStatusBarViewState].
extension AcpStatusBarViewStatePatterns on AcpStatusBarViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpStatusBarViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpStatusBarViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpStatusBarViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpStatusBarViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpStatusBarViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpStatusBarViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpSessionStatusPhase phase,  AcpStopReasonKind? stopReason,  String? stopReasonRaw,  AcpHistoryOriginKind? provenance,  AcpUsagePresentation? usage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpStatusBarViewState() when $default != null:
return $default(_that.phase,_that.stopReason,_that.stopReasonRaw,_that.provenance,_that.usage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpSessionStatusPhase phase,  AcpStopReasonKind? stopReason,  String? stopReasonRaw,  AcpHistoryOriginKind? provenance,  AcpUsagePresentation? usage)  $default,) {final _that = this;
switch (_that) {
case _AcpStatusBarViewState():
return $default(_that.phase,_that.stopReason,_that.stopReasonRaw,_that.provenance,_that.usage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpSessionStatusPhase phase,  AcpStopReasonKind? stopReason,  String? stopReasonRaw,  AcpHistoryOriginKind? provenance,  AcpUsagePresentation? usage)?  $default,) {final _that = this;
switch (_that) {
case _AcpStatusBarViewState() when $default != null:
return $default(_that.phase,_that.stopReason,_that.stopReasonRaw,_that.provenance,_that.usage);case _:
  return null;

}
}

}

/// @nodoc


class _AcpStatusBarViewState implements AcpStatusBarViewState {
  const _AcpStatusBarViewState({required this.phase, this.stopReason, this.stopReasonRaw, this.provenance, this.usage});


@override final  AcpSessionStatusPhase phase;
@override final  AcpStopReasonKind? stopReason;
@override final  String? stopReasonRaw;
@override final  AcpHistoryOriginKind? provenance;
@override final  AcpUsagePresentation? usage;

/// Create a copy of AcpStatusBarViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpStatusBarViewStateCopyWith<_AcpStatusBarViewState> get copyWith => __$AcpStatusBarViewStateCopyWithImpl<_AcpStatusBarViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpStatusBarViewState&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.stopReason, stopReason) || other.stopReason == stopReason)&&(identical(other.stopReasonRaw, stopReasonRaw) || other.stopReasonRaw == stopReasonRaw)&&(identical(other.provenance, provenance) || other.provenance == provenance)&&(identical(other.usage, usage) || other.usage == usage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,stopReason,stopReasonRaw,provenance,usage);
}

@override
String toString() {
    return 'AcpStatusBarViewState(phase: $phase, stopReason: $stopReason, stopReasonRaw: $stopReasonRaw, provenance: $provenance, usage: $usage)';
}


}

/// @nodoc
abstract mixin class _$AcpStatusBarViewStateCopyWith<$Res> implements $AcpStatusBarViewStateCopyWith<$Res> {
  factory _$AcpStatusBarViewStateCopyWith(_AcpStatusBarViewState value, $Res Function(_AcpStatusBarViewState) _then) = __$AcpStatusBarViewStateCopyWithImpl;
@override @useResult
$Res call({
 AcpSessionStatusPhase phase, AcpStopReasonKind? stopReason, String? stopReasonRaw, AcpHistoryOriginKind? provenance, AcpUsagePresentation? usage
});


@override $AcpUsagePresentationCopyWith<$Res>? get usage;

}
/// @nodoc
class __$AcpStatusBarViewStateCopyWithImpl<$Res>
    implements _$AcpStatusBarViewStateCopyWith<$Res> {
  __$AcpStatusBarViewStateCopyWithImpl(this._self, this._then);

  final _AcpStatusBarViewState _self;
  final $Res Function(_AcpStatusBarViewState) _then;

/// Create a copy of AcpStatusBarViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? stopReason = freezed,Object? stopReasonRaw = freezed,Object? provenance = freezed,Object? usage = freezed,}) {
  return _then(_AcpStatusBarViewState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AcpSessionStatusPhase,stopReason: freezed == stopReason ? _self.stopReason : stopReason // ignore: cast_nullable_to_non_nullable
as AcpStopReasonKind?,stopReasonRaw: freezed == stopReasonRaw ? _self.stopReasonRaw : stopReasonRaw // ignore: cast_nullable_to_non_nullable
as String?,provenance: freezed == provenance ? _self.provenance : provenance // ignore: cast_nullable_to_non_nullable
as AcpHistoryOriginKind?,usage: freezed == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as AcpUsagePresentation?,
  ));
}

/// Create a copy of AcpStatusBarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpUsagePresentationCopyWith<$Res>? get usage {
    if (_self.usage == null) {
    return null;
  }

  return $AcpUsagePresentationCopyWith<$Res>(_self.usage!, (value) {
    return _then(_self.copyWith(usage: value));
  });
}
}

/// @nodoc
mixin _$AcpExternalHistoryButtonState {

 AcpExternalHistoryAvailability get status; bool get canLoad; bool get canResume;
/// Create a copy of AcpExternalHistoryButtonState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpExternalHistoryButtonStateCopyWith<AcpExternalHistoryButtonState> get copyWith => _$AcpExternalHistoryButtonStateCopyWithImpl<AcpExternalHistoryButtonState>(this as AcpExternalHistoryButtonState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpExternalHistoryButtonState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpExternalHistoryButtonState&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.canLoad, _this.canLoad) || other.canLoad == _this.canLoad)&&(identical(other.canResume, _this.canResume) || other.canResume == _this.canResume));
}


@override
int get hashCode {
  final _this = this as AcpExternalHistoryButtonState;
  return Object.hash(runtimeType,_this.status,_this.canLoad,_this.canResume);
}

@override
String toString() {
  final _this = this as AcpExternalHistoryButtonState;
  return 'AcpExternalHistoryButtonState(status: ${_this.status}, canLoad: ${_this.canLoad}, canResume: ${_this.canResume})';
}


}

/// @nodoc
abstract mixin class $AcpExternalHistoryButtonStateCopyWith<$Res>  {
  factory $AcpExternalHistoryButtonStateCopyWith(AcpExternalHistoryButtonState value, $Res Function(AcpExternalHistoryButtonState) _then) = _$AcpExternalHistoryButtonStateCopyWithImpl;
@useResult
$Res call({
 AcpExternalHistoryAvailability status, bool canLoad, bool canResume
});




}
/// @nodoc
class _$AcpExternalHistoryButtonStateCopyWithImpl<$Res>
    implements $AcpExternalHistoryButtonStateCopyWith<$Res> {
  _$AcpExternalHistoryButtonStateCopyWithImpl(this._self, this._then);

  final AcpExternalHistoryButtonState _self;
  final $Res Function(AcpExternalHistoryButtonState) _then;

/// Create a copy of AcpExternalHistoryButtonState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? canLoad = null,Object? canResume = null,}) {
  return _then(AcpExternalHistoryButtonState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as AcpExternalHistoryAvailability,canLoad: null == canLoad ? _self.canLoad : canLoad // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpExternalHistoryButtonState].
extension AcpExternalHistoryButtonStatePatterns on AcpExternalHistoryButtonState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpExternalHistoryButtonState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpExternalHistoryButtonState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpExternalHistoryButtonState value)  $default,){
final _that = this;
switch (_that) {
case _AcpExternalHistoryButtonState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpExternalHistoryButtonState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpExternalHistoryButtonState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpExternalHistoryAvailability status,  bool canLoad,  bool canResume)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpExternalHistoryButtonState() when $default != null:
return $default(_that.status,_that.canLoad,_that.canResume);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpExternalHistoryAvailability status,  bool canLoad,  bool canResume)  $default,) {final _that = this;
switch (_that) {
case _AcpExternalHistoryButtonState():
return $default(_that.status,_that.canLoad,_that.canResume);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpExternalHistoryAvailability status,  bool canLoad,  bool canResume)?  $default,) {final _that = this;
switch (_that) {
case _AcpExternalHistoryButtonState() when $default != null:
return $default(_that.status,_that.canLoad,_that.canResume);case _:
  return null;

}
}

}

/// @nodoc


class _AcpExternalHistoryButtonState implements AcpExternalHistoryButtonState {
  const _AcpExternalHistoryButtonState({required this.status, this.canLoad = false, this.canResume = false});


@override final  AcpExternalHistoryAvailability status;
@override@JsonKey() final  bool canLoad;
@override@JsonKey() final  bool canResume;

/// Create a copy of AcpExternalHistoryButtonState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpExternalHistoryButtonStateCopyWith<_AcpExternalHistoryButtonState> get copyWith => __$AcpExternalHistoryButtonStateCopyWithImpl<_AcpExternalHistoryButtonState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpExternalHistoryButtonState&&(identical(other.status, status) || other.status == status)&&(identical(other.canLoad, canLoad) || other.canLoad == canLoad)&&(identical(other.canResume, canResume) || other.canResume == canResume));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,canLoad,canResume);
}

@override
String toString() {
    return 'AcpExternalHistoryButtonState(status: $status, canLoad: $canLoad, canResume: $canResume)';
}


}

/// @nodoc
abstract mixin class _$AcpExternalHistoryButtonStateCopyWith<$Res> implements $AcpExternalHistoryButtonStateCopyWith<$Res> {
  factory _$AcpExternalHistoryButtonStateCopyWith(_AcpExternalHistoryButtonState value, $Res Function(_AcpExternalHistoryButtonState) _then) = __$AcpExternalHistoryButtonStateCopyWithImpl;
@override @useResult
$Res call({
 AcpExternalHistoryAvailability status, bool canLoad, bool canResume
});




}
/// @nodoc
class __$AcpExternalHistoryButtonStateCopyWithImpl<$Res>
    implements _$AcpExternalHistoryButtonStateCopyWith<$Res> {
  __$AcpExternalHistoryButtonStateCopyWithImpl(this._self, this._then);

  final _AcpExternalHistoryButtonState _self;
  final $Res Function(_AcpExternalHistoryButtonState) _then;

/// Create a copy of AcpExternalHistoryButtonState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? canLoad = null,Object? canResume = null,}) {
  return _then(_AcpExternalHistoryButtonState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as AcpExternalHistoryAvailability,canLoad: null == canLoad ? _self.canLoad : canLoad // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$AcpExternalSessionRowPresentation {

 String get sessionId; String? get title; String get cwd; String? get updatedAt; AcpExternalOpenOutcome? get outcome; String? get errorMessage;
/// Create a copy of AcpExternalSessionRowPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpExternalSessionRowPresentationCopyWith<AcpExternalSessionRowPresentation> get copyWith => _$AcpExternalSessionRowPresentationCopyWithImpl<AcpExternalSessionRowPresentation>(this as AcpExternalSessionRowPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpExternalSessionRowPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpExternalSessionRowPresentation&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.cwd, _this.cwd) || other.cwd == _this.cwd)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}


@override
int get hashCode {
  final _this = this as AcpExternalSessionRowPresentation;
  return Object.hash(runtimeType,_this.sessionId,_this.title,_this.cwd,_this.updatedAt,_this.outcome,_this.errorMessage);
}

@override
String toString() {
  final _this = this as AcpExternalSessionRowPresentation;
  return 'AcpExternalSessionRowPresentation(sessionId: ${_this.sessionId}, title: ${_this.title}, cwd: ${_this.cwd}, updatedAt: ${_this.updatedAt}, outcome: ${_this.outcome}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $AcpExternalSessionRowPresentationCopyWith<$Res>  {
  factory $AcpExternalSessionRowPresentationCopyWith(AcpExternalSessionRowPresentation value, $Res Function(AcpExternalSessionRowPresentation) _then) = _$AcpExternalSessionRowPresentationCopyWithImpl;
@useResult
$Res call({
 String sessionId, String? title, String cwd, String? updatedAt, AcpExternalOpenOutcome? outcome, String? errorMessage
});




}
/// @nodoc
class _$AcpExternalSessionRowPresentationCopyWithImpl<$Res>
    implements $AcpExternalSessionRowPresentationCopyWith<$Res> {
  _$AcpExternalSessionRowPresentationCopyWithImpl(this._self, this._then);

  final AcpExternalSessionRowPresentation _self;
  final $Res Function(AcpExternalSessionRowPresentation) _then;

/// Create a copy of AcpExternalSessionRowPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? title = freezed,Object? cwd = null,Object? updatedAt = freezed,Object? outcome = freezed,Object? errorMessage = freezed,}) {
  return _then(AcpExternalSessionRowPresentation(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AcpExternalOpenOutcome?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpExternalSessionRowPresentation].
extension AcpExternalSessionRowPresentationPatterns on AcpExternalSessionRowPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpExternalSessionRowPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpExternalSessionRowPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpExternalSessionRowPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpExternalSessionRowPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpExternalSessionRowPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpExternalSessionRowPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String? title,  String cwd,  String? updatedAt,  AcpExternalOpenOutcome? outcome,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpExternalSessionRowPresentation() when $default != null:
return $default(_that.sessionId,_that.title,_that.cwd,_that.updatedAt,_that.outcome,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String? title,  String cwd,  String? updatedAt,  AcpExternalOpenOutcome? outcome,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _AcpExternalSessionRowPresentation():
return $default(_that.sessionId,_that.title,_that.cwd,_that.updatedAt,_that.outcome,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String? title,  String cwd,  String? updatedAt,  AcpExternalOpenOutcome? outcome,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _AcpExternalSessionRowPresentation() when $default != null:
return $default(_that.sessionId,_that.title,_that.cwd,_that.updatedAt,_that.outcome,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _AcpExternalSessionRowPresentation implements AcpExternalSessionRowPresentation {
  const _AcpExternalSessionRowPresentation({required this.sessionId, this.title, required this.cwd, this.updatedAt, this.outcome, this.errorMessage});


@override final  String sessionId;
@override final  String? title;
@override final  String cwd;
@override final  String? updatedAt;
@override final  AcpExternalOpenOutcome? outcome;
@override final  String? errorMessage;

/// Create a copy of AcpExternalSessionRowPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpExternalSessionRowPresentationCopyWith<_AcpExternalSessionRowPresentation> get copyWith => __$AcpExternalSessionRowPresentationCopyWithImpl<_AcpExternalSessionRowPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpExternalSessionRowPresentation&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.title, title) || other.title == title)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,title,cwd,updatedAt,outcome,errorMessage);
}

@override
String toString() {
    return 'AcpExternalSessionRowPresentation(sessionId: $sessionId, title: $title, cwd: $cwd, updatedAt: $updatedAt, outcome: $outcome, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$AcpExternalSessionRowPresentationCopyWith<$Res> implements $AcpExternalSessionRowPresentationCopyWith<$Res> {
  factory _$AcpExternalSessionRowPresentationCopyWith(_AcpExternalSessionRowPresentation value, $Res Function(_AcpExternalSessionRowPresentation) _then) = __$AcpExternalSessionRowPresentationCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String? title, String cwd, String? updatedAt, AcpExternalOpenOutcome? outcome, String? errorMessage
});




}
/// @nodoc
class __$AcpExternalSessionRowPresentationCopyWithImpl<$Res>
    implements _$AcpExternalSessionRowPresentationCopyWith<$Res> {
  __$AcpExternalSessionRowPresentationCopyWithImpl(this._self, this._then);

  final _AcpExternalSessionRowPresentation _self;
  final $Res Function(_AcpExternalSessionRowPresentation) _then;

/// Create a copy of AcpExternalSessionRowPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? title = freezed,Object? cwd = null,Object? updatedAt = freezed,Object? outcome = freezed,Object? errorMessage = freezed,}) {
  return _then(_AcpExternalSessionRowPresentation(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AcpExternalOpenOutcome?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AcpExternalHistoryDialogState {

 AcpExternalHistoryAvailability get availability; bool get canLoad; bool get canResume; List<AcpExternalSessionRowPresentation> get sessions; String? get nextCursor; bool get loading; bool get loadingMore; bool get anyOpening; String? get listError;
/// Create a copy of AcpExternalHistoryDialogState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpExternalHistoryDialogStateCopyWith<AcpExternalHistoryDialogState> get copyWith => _$AcpExternalHistoryDialogStateCopyWithImpl<AcpExternalHistoryDialogState>(this as AcpExternalHistoryDialogState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpExternalHistoryDialogState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpExternalHistoryDialogState&&(identical(other.availability, _this.availability) || other.availability == _this.availability)&&(identical(other.canLoad, _this.canLoad) || other.canLoad == _this.canLoad)&&(identical(other.canResume, _this.canResume) || other.canResume == _this.canResume)&&const DeepCollectionEquality().equals(other.sessions, _this.sessions)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.loadingMore, _this.loadingMore) || other.loadingMore == _this.loadingMore)&&(identical(other.anyOpening, _this.anyOpening) || other.anyOpening == _this.anyOpening)&&(identical(other.listError, _this.listError) || other.listError == _this.listError));
}


@override
int get hashCode {
  final _this = this as AcpExternalHistoryDialogState;
  return Object.hash(runtimeType,_this.availability,_this.canLoad,_this.canResume,const DeepCollectionEquality().hash(_this.sessions),_this.nextCursor,_this.loading,_this.loadingMore,_this.anyOpening,_this.listError);
}

@override
String toString() {
  final _this = this as AcpExternalHistoryDialogState;
  return 'AcpExternalHistoryDialogState(availability: ${_this.availability}, canLoad: ${_this.canLoad}, canResume: ${_this.canResume}, sessions: ${_this.sessions}, nextCursor: ${_this.nextCursor}, loading: ${_this.loading}, loadingMore: ${_this.loadingMore}, anyOpening: ${_this.anyOpening}, listError: ${_this.listError})';
}


}

/// @nodoc
abstract mixin class $AcpExternalHistoryDialogStateCopyWith<$Res>  {
  factory $AcpExternalHistoryDialogStateCopyWith(AcpExternalHistoryDialogState value, $Res Function(AcpExternalHistoryDialogState) _then) = _$AcpExternalHistoryDialogStateCopyWithImpl;
@useResult
$Res call({
 AcpExternalHistoryAvailability availability, bool canLoad, bool canResume, List<AcpExternalSessionRowPresentation> sessions, String? nextCursor, bool loading, bool loadingMore, bool anyOpening, String? listError
});




}
/// @nodoc
class _$AcpExternalHistoryDialogStateCopyWithImpl<$Res>
    implements $AcpExternalHistoryDialogStateCopyWith<$Res> {
  _$AcpExternalHistoryDialogStateCopyWithImpl(this._self, this._then);

  final AcpExternalHistoryDialogState _self;
  final $Res Function(AcpExternalHistoryDialogState) _then;

/// Create a copy of AcpExternalHistoryDialogState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? availability = null,Object? canLoad = null,Object? canResume = null,Object? sessions = null,Object? nextCursor = freezed,Object? loading = null,Object? loadingMore = null,Object? anyOpening = null,Object? listError = freezed,}) {
  return _then(AcpExternalHistoryDialogState(
availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as AcpExternalHistoryAvailability,canLoad: null == canLoad ? _self.canLoad : canLoad // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<AcpExternalSessionRowPresentation>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,anyOpening: null == anyOpening ? _self.anyOpening : anyOpening // ignore: cast_nullable_to_non_nullable
as bool,listError: freezed == listError ? _self.listError : listError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpExternalHistoryDialogState].
extension AcpExternalHistoryDialogStatePatterns on AcpExternalHistoryDialogState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpExternalHistoryDialogState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpExternalHistoryDialogState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpExternalHistoryDialogState value)  $default,){
final _that = this;
switch (_that) {
case _AcpExternalHistoryDialogState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpExternalHistoryDialogState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpExternalHistoryDialogState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpExternalHistoryAvailability availability,  bool canLoad,  bool canResume,  List<AcpExternalSessionRowPresentation> sessions,  String? nextCursor,  bool loading,  bool loadingMore,  bool anyOpening,  String? listError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpExternalHistoryDialogState() when $default != null:
return $default(_that.availability,_that.canLoad,_that.canResume,_that.sessions,_that.nextCursor,_that.loading,_that.loadingMore,_that.anyOpening,_that.listError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpExternalHistoryAvailability availability,  bool canLoad,  bool canResume,  List<AcpExternalSessionRowPresentation> sessions,  String? nextCursor,  bool loading,  bool loadingMore,  bool anyOpening,  String? listError)  $default,) {final _that = this;
switch (_that) {
case _AcpExternalHistoryDialogState():
return $default(_that.availability,_that.canLoad,_that.canResume,_that.sessions,_that.nextCursor,_that.loading,_that.loadingMore,_that.anyOpening,_that.listError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpExternalHistoryAvailability availability,  bool canLoad,  bool canResume,  List<AcpExternalSessionRowPresentation> sessions,  String? nextCursor,  bool loading,  bool loadingMore,  bool anyOpening,  String? listError)?  $default,) {final _that = this;
switch (_that) {
case _AcpExternalHistoryDialogState() when $default != null:
return $default(_that.availability,_that.canLoad,_that.canResume,_that.sessions,_that.nextCursor,_that.loading,_that.loadingMore,_that.anyOpening,_that.listError);case _:
  return null;

}
}

}

/// @nodoc


class _AcpExternalHistoryDialogState implements AcpExternalHistoryDialogState {
  const _AcpExternalHistoryDialogState({required this.availability, this.canLoad = false, this.canResume = false,  List<AcpExternalSessionRowPresentation> sessions = const <AcpExternalSessionRowPresentation>[], this.nextCursor, this.loading = false, this.loadingMore = false, this.anyOpening = false, this.listError}): _sessions = sessions;


@override final  AcpExternalHistoryAvailability availability;
@override@JsonKey() final  bool canLoad;
@override@JsonKey() final  bool canResume;
 final  List<AcpExternalSessionRowPresentation> _sessions;
@override@JsonKey() List<AcpExternalSessionRowPresentation> get sessions {
  if (_sessions is EqualUnmodifiableListView) return _sessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sessions);
}

@override final  String? nextCursor;
@override@JsonKey() final  bool loading;
@override@JsonKey() final  bool loadingMore;
@override@JsonKey() final  bool anyOpening;
@override final  String? listError;

/// Create a copy of AcpExternalHistoryDialogState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpExternalHistoryDialogStateCopyWith<_AcpExternalHistoryDialogState> get copyWith => __$AcpExternalHistoryDialogStateCopyWithImpl<_AcpExternalHistoryDialogState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpExternalHistoryDialogState&&(identical(other.availability, availability) || other.availability == availability)&&(identical(other.canLoad, canLoad) || other.canLoad == canLoad)&&(identical(other.canResume, canResume) || other.canResume == canResume)&&const DeepCollectionEquality().equals(other.sessions, _sessions)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.anyOpening, anyOpening) || other.anyOpening == anyOpening)&&(identical(other.listError, listError) || other.listError == listError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,availability,canLoad,canResume,const DeepCollectionEquality().hash(_sessions),nextCursor,loading,loadingMore,anyOpening,listError);
}

@override
String toString() {
    return 'AcpExternalHistoryDialogState(availability: $availability, canLoad: $canLoad, canResume: $canResume, sessions: $sessions, nextCursor: $nextCursor, loading: $loading, loadingMore: $loadingMore, anyOpening: $anyOpening, listError: $listError)';
}


}

/// @nodoc
abstract mixin class _$AcpExternalHistoryDialogStateCopyWith<$Res> implements $AcpExternalHistoryDialogStateCopyWith<$Res> {
  factory _$AcpExternalHistoryDialogStateCopyWith(_AcpExternalHistoryDialogState value, $Res Function(_AcpExternalHistoryDialogState) _then) = __$AcpExternalHistoryDialogStateCopyWithImpl;
@override @useResult
$Res call({
 AcpExternalHistoryAvailability availability, bool canLoad, bool canResume, List<AcpExternalSessionRowPresentation> sessions, String? nextCursor, bool loading, bool loadingMore, bool anyOpening, String? listError
});




}
/// @nodoc
class __$AcpExternalHistoryDialogStateCopyWithImpl<$Res>
    implements _$AcpExternalHistoryDialogStateCopyWith<$Res> {
  __$AcpExternalHistoryDialogStateCopyWithImpl(this._self, this._then);

  final _AcpExternalHistoryDialogState _self;
  final $Res Function(_AcpExternalHistoryDialogState) _then;

/// Create a copy of AcpExternalHistoryDialogState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? availability = null,Object? canLoad = null,Object? canResume = null,Object? sessions = null,Object? nextCursor = freezed,Object? loading = null,Object? loadingMore = null,Object? anyOpening = null,Object? listError = freezed,}) {
  return _then(_AcpExternalHistoryDialogState(
availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as AcpExternalHistoryAvailability,canLoad: null == canLoad ? _self.canLoad : canLoad // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,sessions: null == sessions ? _self._sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<AcpExternalSessionRowPresentation>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,anyOpening: null == anyOpening ? _self.anyOpening : anyOpening // ignore: cast_nullable_to_non_nullable
as bool,listError: freezed == listError ? _self.listError : listError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
