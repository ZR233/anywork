import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Declarations that decide owner classification for one analysed workspace.
///
/// Ownership follows declaration kind and location instead of the spelling of a
/// type name: a Freezed value, an enum and their generated companions are values
/// even when they are called `*Owner` or `*Connection`, and a type declared in a
/// feature's UI layer is a Dumb-view prop instead of a business owner.
void collectBoundaryDeclarations({
  required CompilationUnit unit,
  required String path,
  required Set<String> valueTypes,
  required Set<String> uiTypes,
}) {
  final uiLayer = _isUiLayerPath(path);
  for (final declaration in unit.declarations) {
    if (declaration is EnumDeclaration) {
      valueTypes.add(_declaredName(declaration.namePart.toSource()));
      continue;
    }
    if (declaration is! ClassDeclaration) continue;
    final name = _declaredName(declaration.namePart.toSource());
    if (declaration.metadata.any(_isFreezedAnnotation)) {
      valueTypes.add(name);
      for (final mixin
          in declaration.withClause?.mixinTypes ?? const <NamedType>[]) {
        valueTypes.add(_declaredName(mixin.toSource()));
      }
      for (final member
          in declaration.body.members.whereType<ConstructorDeclaration>()) {
        final redirect = member.factoryRedirectionTarget;
        if (redirect != null) {
          valueTypes.add(_declaredName(redirect.typeReference.toSource()));
        }
      }
    }
    if (uiLayer || _isWidgetDeclaration(declaration)) uiTypes.add(name);
  }
}

String _declaredName(String source) =>
    source.split('<').first.split('.').last.trim();

bool _isFreezedAnnotation(Annotation annotation) => const {
  'freezed',
  'Freezed',
}.contains(annotation.name.toSource().split('.').last);

bool _isUiLayerPath(String path) =>
    path.contains('/views/') ||
    path.contains('/widgets/') ||
    path.contains('/src/ui/');

/// Widget-layer vocabulary. These are props of a Dumb view, not owners.
const _widgetSupertypes = {
  'Widget',
  'StatefulWidget',
  'StatelessWidget',
  'State',
  'ConsumerWidget',
  'ConsumerState',
  'ConsumerStatefulWidget',
  'HookWidget',
  'PreferredSizeWidget',
};

bool _isWidgetDeclaration(ClassDeclaration node) {
  final supertypes = <NamedType>[
    if (node.extendsClause case final clause?) clause.superclass,
    ...?node.withClause?.mixinTypes,
    ...?node.implementsClause?.interfaces,
  ];
  return supertypes.any(
    (type) => _widgetSupertypes.contains(_declaredName(type.toSource())),
  );
}

/// Feature-First syntax contracts shared by the CLI and negative fixtures.
/// This does not infer runtime ownership from names: resource joins, reducers
/// and ViewModel intent handling still require their behavioral suites.
void checkFeatureBoundaries({
  required CompilationUnit unit,
  required String path,
  required void Function(int offset, String rule, String message) report,
  Set<String> valueTypes = const <String>{},
  Set<String> uiTypes = const <String>{},
}) {
  unit.accept(
    _FeatureBoundaryVisitor(
      path: path,
      report: report,
      valueTypes: valueTypes,
      uiTypes: uiTypes,
    ),
  );
}

final class _FeatureBoundaryVisitor extends RecursiveAstVisitor<void> {
  _FeatureBoundaryVisitor({
    required this.path,
    required this.report,
    required this.valueTypes,
    required this.uiTypes,
  });

  final String path;
  final void Function(int offset, String rule, String message) report;
  final Set<String> valueTypes;
  final Set<String> uiTypes;
  final _classes = <String>[];
  final _uiGraphPrefixes = <String>{};
  final _observationHolders = <String>{};
  var _valueDepth = 0;

  bool get _isClient => path.startsWith('code/anywork_client/lib/');
  bool get _isFeature => path.startsWith('code/anywork/lib/src/features/');
  bool get _isAdapter =>
      path.startsWith('code/anywork/lib/src/infrastructure/frb/');
  bool get _isDiagnostics =>
      path.startsWith('code/anywork/lib/src/diagnostics/');
  bool get _isDumbPath =>
      path.startsWith('code/anywork/lib/src/ui/') ||
      _isFeature && (path.contains('/views/') || path.contains('/widgets/'));
  bool get _isDumb =>
      _isDumbPath ||
      _isFeature &&
          _classes.any(
            (name) => name.endsWith('View') || name.endsWith('Widget'),
          );
  bool get _isStatePath => _isFeature && path.contains('/state/');
  bool get _isViewModel => _isFeature && path.contains('/view_models/');

  @override
  void visitImportDirective(ImportDirective node) {
    if (node.uri.stringValue == 'package:vyuh_node_flow/vyuh_node_flow.dart' &&
        node.configurations.isEmpty) {
      _uiGraphPrefixes.add(node.prefix?.toSource() ?? '');
    }
    _checkUri(node.uri);
    for (final configuration in node.configurations) {
      _checkUri(configuration.uri);
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _checkUri(node.uri);
    _checkDomainExport(node.uri);
    for (final configuration in node.configurations) {
      _checkUri(configuration.uri);
      _checkDomainExport(configuration.uri);
    }
    super.visitExportDirective(node);
  }

  void _checkDomainExport(StringLiteral literal) {
    final match = RegExp(r'^code/anywork_client/lib/([a-z_]+)\.dart$')
        .firstMatch(path);
    final domain = match?.group(1);
    if (domain == null || domain.endsWith('_ports')) return;
    final uri = literal.stringValue;
    if (uri == null) return;
    final prefix =
        const {
          'remote',
          'recovery',
          'persistence',
          'mcp',
          'lsp',
          'skills',
        }.contains(domain)
        ? 'src/resources/$domain/'
        : 'src/$domain/';
    final resolved = _sourcePath(path, uri);
    if (!resolved.startsWith('code/anywork_client/lib/${prefix}domain/')) {
      report(
        literal.offset,
        'EXPORT-01',
        'A domain barrel must export only its own public values/capabilities: $uri',
      );
    }
  }

  void _checkUri(StringLiteral literal) {
    final uri = literal.stringValue;
    if (uri == null) return;
    final resolved = _sourcePath(path, uri);
    if (const {
          'studio_client.dart',
          'anywork_client.dart',
          'studio_ports.dart',
          'transport_ports.dart',
        }.contains(uri.split('/').last) ||
        resolved.contains('/presentation/providers/') ||
        resolved.contains('/src/studio/application/') ||
        resolved.contains('/src/chat/') ||
        resolved.contains('/domain/models/')) {
      report(
        literal.offset,
        'OLD-01',
        'Removed facade or forwarding path: $uri',
      );
    }
    if (_isDumbPath &&
        (uri.contains('riverpod') ||
            uri.contains('flutter_rust_bridge') ||
            uri.endsWith('_ports.dart') ||
            resolved.contains('/infrastructure/') ||
            resolved.contains('/view_models/') ||
            resolved.contains('/src/app/') &&
                !resolved.contains('/src/app/theme/') ||
            resolved.contains('/src/rust/') ||
            _serviceLocatorUri(uri))) {
      report(literal.offset, 'UI-02', 'Dumb UI cannot import an owner: $uri');
    }
    if (_isStatePath &&
        (uri.startsWith('package:flutter/') ||
            uri.contains('riverpod') ||
            uri.contains('flutter_rust_bridge') ||
            resolved.contains('/infrastructure/') ||
            resolved.contains('/src/rust/') ||
            uri.endsWith('_ports.dart'))) {
      report(
        literal.offset,
        'STATE-01',
        'ViewState must contain values only: $uri',
      );
    }
    if (_isViewModel &&
        (uri.startsWith('package:flutter/') ||
            resolved.contains('/views/') ||
            resolved.contains('/widgets/') ||
            resolved.contains('/src/ui/'))) {
      report(
        literal.offset,
        'VM-01',
        'ViewModel cannot depend on Widgets: $uri',
      );
    }
    if (_isAdapter &&
        (resolved.contains('/features/') ||
            resolved.contains('/src/app/') ||
            uri.contains('riverpod') ||
            _serviceLocatorUri(uri))) {
      report(
        literal.offset,
        'ADAPTER-01',
        'Typed adapter cannot own presentation: $uri',
      );
    }
    if (_isDiagnostics &&
        (resolved.contains('/features/') &&
                const [
                  '/view_models/',
                  '/state/',
                  '/timeline/',
                  '/views/',
                  '/widgets/',
                ].any(resolved.contains) ||
            resolved.contains('/infrastructure/') ||
            resolved.contains('/src/rust/') ||
            uri.endsWith('_ports.dart'))) {
      report(
        literal.offset,
        'DIAG-01',
        'Diagnostics must borrow public projections: $uri',
      );
    }
  }

  @override
  void visitPartDirective(PartDirective node) {
    final uri = node.uri.stringValue ?? '';
    if (!_isGeneratedPart &&
        !uri.endsWith('.g.dart') &&
        !uri.endsWith('.freezed.dart') &&
        !_isModuleInternalPart(uri)) {
      report(
        node.offset,
        'OLD-02',
        'A handwritten part must stay in one module directory: $uri',
      );
    }
    super.visitPartDirective(node);
  }

  @override
  void visitPartOfDirective(PartOfDirective node) {
    final uri = node.uri?.stringValue ?? '';
    if (!_isGeneratedPart && !_isModuleInternalPart(uri)) {
      report(
        node.offset,
        'OLD-02',
        'A handwritten part-of must stay in one module directory: $uri',
      );
    }
    super.visitPartOfDirective(node);
  }

  /// Generated parts belong to the canonical generation boundary, not to this
  /// handwritten-layout rule.
  bool get _isGeneratedPart =>
      path.endsWith('.g.dart') || path.endsWith('.freezed.dart');

  /// A handwritten part is module-internal organization only when the part file
  /// sits in the same directory and that directory is a Client domain `data/`
  /// module or the frb adapter layer.
  bool _isModuleInternalPart(String uri) {
    if (uri.isEmpty ||
        uri.startsWith('package:') ||
        uri.startsWith('dart:') ||
        uri.startsWith('/')) {
      return false;
    }
    final directory = path.substring(0, path.lastIndexOf('/') + 1);
    if (directory.isEmpty) return false;
    final resolved = _sourcePath(path, uri);
    if (!resolved.startsWith(directory)) return false;
    if (resolved.substring(directory.length).contains('/')) return false;
    return _isInternalModuleDirectory(directory);
  }

  bool _isInternalModuleDirectory(String directory) =>
      RegExp(r'^code/anywork_client/lib/src/(?:[a-z][a-z_]*/)+data/$')
          .hasMatch(directory) ||
      directory.startsWith('code/anywork/lib/src/infrastructure/frb/');

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.namePart.toSource().split(RegExp(r'[<(]')).first;
    _classes.add(name);
    if (_legacyOwner(name)) {
      report(node.offset, 'OLD-01', 'Removed facade declaration: $name');
    }
    final isValue = node.metadata.any(
      (annotation) => const {
        'freezed',
        'Freezed',
      }.contains(annotation.name.toSource().split('.').last),
    );
    if (isValue) _valueDepth++;
    if (_isViewModel && name.endsWith('ViewModel')) {
      final generated =
          node.extendsClause?.superclass.name.lexeme == '_\$$name';
      final annotated = node.metadata.any(
        (annotation) => const {
          'riverpod',
          'Riverpod',
        }.contains(annotation.name.toSource().split('.').last),
      );
      if (!generated || !annotated) {
        report(
          node.offset,
          'VM-02',
          'ViewModel must use a generated AsyncNotifier declaration',
        );
      }
      final build = node.body.members.whereType<MethodDeclaration>().where(
        (method) => method.name.lexeme == 'build',
      );
      if (build.isEmpty ||
          build.any((method) {
            final type = method.returnType;
            return type is! NamedType ||
                !const {'Future', 'FutureOr'}.contains(type.name.lexeme) ||
                type.typeArguments?.arguments.length != 1;
          })) {
        report(
          node.offset,
          'VM-02',
          'AsyncNotifier build must explicitly return Future/FutureOr of its ViewState',
        );
      }
      for (final method in build) {
        final body = method.body;
        final expression = switch (body) {
          ExpressionFunctionBody() => body.expression,
          BlockFunctionBody() when body.block.statements.length == 1 =>
            switch (body.block.statements.single) {
              ReturnStatement(:final expression) => expression,
              _ => null,
            },
          _ => null,
        };
        if (expression is PropertyAccess &&
                const {
                  'state',
                  'value',
                }.contains(expression.propertyName.name) ||
            expression is PrefixedIdentifier &&
                const {'state', 'value'}.contains(expression.identifier.name)) {
          report(
            method.offset,
            'VM-03',
            'A direct canonical read is not an editing/intent ViewModel',
          );
        }
      }
    }
    super.visitClassDeclaration(node);
    if (isValue) _valueDepth--;
    _classes.removeLast();
  }

  /// An adapter may publish into the latest-value holder it owns and exposes as
  /// read-only observation; that is producer-side publication, not a second
  /// canonical mirror.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    // The current parser models `Holder<T>(...)` as an unqualified invocation.
    final initializer = node.initializer;
    final constructed = switch (initializer) {
      InstanceCreationExpression() => _declaredName(
        initializer.constructorName.type.toSource(),
      ),
      MethodInvocation() when initializer.target == null =>
        initializer.methodName.name,
      _ => null,
    };
    if (constructed != null &&
        const {
          'LatestValue',
          'ReadonlyLatestValue',
          'CoalescedPublish',
        }.contains(constructed)) {
      _observationHolders.add(node.name.lexeme);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if (_legacyOwner(name)) {
      report(node.offset, 'OLD-01', 'Removed facade type: $name');
    }
    final typeName = node.toSource().split('<').first;
    final qualifier = typeName.contains('.') ? typeName.split('.').first : '';
    final uiGraphEdge =
        _uiGraphVocabulary.contains(name) &&
        _uiGraphPrefixes.contains(qualifier);
    if (_isDumb && _businessOwner(name) && !uiGraphEdge) {
      report(node.offset, 'UI-02', 'Dumb UI cannot receive or create $name');
    }
    if ((_isStatePath || _valueDepth > 0) && _runtimeOwner(name)) {
      report(
        node.offset,
        'STATE-01',
        'Immutable state cannot contain runtime owner $name',
      );
    }
    if (_isAdapter &&
        (name.endsWith('ViewModel') ||
            name.endsWith('ViewState') ||
            name.endsWith('Repository') ||
            name == 'OperationRegistry' ||
            name == 'LatestValue')) {
      report(
        node.offset,
        'ADAPTER-01',
        'Adapter must convert typed values, not own $name',
      );
    }
    if (_isClient &&
        (name.startsWith('Bridge') ||
            const {
              'FlutterRustBridgeBase',
              'RustLib',
              'RustStreamSink',
            }.contains(name))) {
      report(
        node.offset,
        'OWN-01',
        'Domain cannot retain generated FRB DTO $name',
      );
    }
    super.visitNamedType(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (_legacyOwner(name)) {
      report(node.offset, 'OLD-01', 'Removed facade constructor: $name');
    }
    if (_isDumb &&
        name.isNotEmpty &&
        RegExp(r'^[A-Z]').hasMatch(name) &&
        _businessOwner(name) &&
        !(_uiGraphVocabulary.contains(name) &&
            _uiGraphPrefixes.contains(node.target?.toSource() ?? ''))) {
      report(
        node.offset,
        'UI-02',
        'Dumb UI cannot construct business owner $name',
      );
    }
    if (_isDumb &&
        (const {'watch', 'read', 'listen'}.contains(name) &&
                const {'ref', 'container'}.contains(node.target?.toSource()) ||
            const {'getIt', 'locate', 'serviceLocator'}.contains(name) ||
            const {
              'getIt',
              'serviceLocator',
            }.contains(node.target?.toSource()))) {
      report(
        node.offset,
        'UI-02',
        'Move business lookup from Dumb UI into its Connector',
      );
    }
    if (_isAdapter &&
        const {'publish', 'markObserved', 'markDurable'}.contains(name) &&
        !_publishesOwnObservation(node)) {
      report(
        node.offset,
        'ADAPTER-01',
        'Adapter cannot write a second canonical reducer',
      );
    }
    super.visitMethodInvocation(node);
  }

  bool _publishesOwnObservation(MethodInvocation node) {
    final target = node.target;
    if (target == null) return false;
    return _observationHolders.contains(
      target.toSource().split('.').last.trim(),
    );
  }

  /// A declared value type or a UI-layer type is never a business owner; only
  /// undecided names fall back to the syntactic suffix families below.
  bool _businessOwner(String name) {
    if (valueTypes.contains(name) || uiTypes.contains(name)) return false;
    return _legacyOwner(name) ||
        const {
          'Ref',
          'WidgetRef',
          'ProviderRef',
          'ProviderContainer',
          'AppGraph',
          'GetIt',
          'ServiceLocator',
        }.contains(name) ||
        name.endsWith('Repository') ||
        name.endsWith('Session') ||
        name.endsWith('ViewModel') ||
        name.endsWith('Port') ||
        name.endsWith('Handle') ||
        name.endsWith('Connection') ||
        name.endsWith('Owner') ||
        name.endsWith('Service') ||
        name.startsWith('Bridge');
  }

  bool _runtimeOwner(String name) {
    if (valueTypes.contains(name)) return false;
    if (_businessOwner(name)) return true;
    return const {
          'Widget',
          'BuildContext',
          'Future',
          'FutureOr',
          'Stream',
          'StreamSubscription',
          'Timer',
          'Completer',
          'Observation',
          'OperationTicket',
          'OperationObservation',
          'ReadonlyLatestValue',
          'LatestValue',
          'ResourcePermit',
          'ResourceBudget',
          'TextEditingController',
        }.contains(name) ||
        name.endsWith('Controller') ||
        name.endsWith('Registry') ||
        name.endsWith('Binding') ||
        name.endsWith('Lease');
  }
}

bool _legacyOwner(String name) => const {
  'AnyworkClient',
  'StudioClient',
  'StudioTransport',
  'StudioState',
  'ModeEditorOwner',
}.contains(name);

/// UI-graph vocabulary of `vyuh_node_flow`: the canvas projection owns
/// coordinates and edges, never a business owner. These names are only accepted
/// in files that import that package.
const _uiGraphVocabulary = {'Connection', 'Port', 'Node', 'NodeGraph'};

bool _serviceLocatorUri(String uri) =>
    uri.startsWith('package:get_it/') ||
    uri.startsWith('package:injectable/') ||
    uri.contains('service_locator');

String _sourcePath(String path, String uri) {
  for (final package in const ['anywork_client', 'anywork']) {
    final prefix = 'package:$package/';
    if (uri.startsWith(prefix)) {
      return Uri(path: 'code/$package/lib/${uri.substring(prefix.length)}')
          .normalizePath()
          .path;
    }
  }
  return Uri(path: path).resolve(uri).normalizePath().toString();
}
