// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TodoViewModel)
final todoViewModelProvider = TodoViewModelFamily._();

final class TodoViewModelProvider
    extends $AsyncNotifierProvider<TodoViewModel, TodoViewState> {
  TodoViewModelProvider._({
    required TodoViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'todoViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$todoViewModelHash();

  @override
  String toString() {
    return r'todoViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TodoViewModel create() => TodoViewModel();

  @override
  bool operator ==(Object other) {
    return other is TodoViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$todoViewModelHash() => r'4299d60bc82ec84903cad872cdd56bc9bcf4385e';

final class TodoViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TodoViewModel,
          AsyncValue<TodoViewState>,
          TodoViewState,
          FutureOr<TodoViewState>,
          String
        > {
  TodoViewModelFamily._()
    : super(
        retry: null,
        name: r'todoViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TodoViewModelProvider call(String threadId) =>
      TodoViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'todoViewModelProvider';
}

abstract class _$TodoViewModel extends $AsyncNotifier<TodoViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<TodoViewState> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<TodoViewState>, TodoViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<TodoViewState>, TodoViewState>,
              AsyncValue<TodoViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
