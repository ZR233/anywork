// Runs through cargo xtask verify-client with anywork's locked analyzer.
// This is a syntax boundary check; runtime ownership is proved by the Client
// and adapter suites, rather than inferred from identifier spelling.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: client_boundary_check.dart <workspace-root>');
    exitCode = 64;
    return;
  }
  final root = Directory(
    Directory(arguments.single).resolveSymbolicLinksSync(),
  );
  final client = Directory('${root.path}/code/anywork_client/lib');
  final app = Directory('${root.path}/code/anywork/lib');
  final diagnostics = <String>[];
  var checked = 0;
  for (final directory in [client, app]) {
    if (!directory.existsSync()) {
      diagnostics.add(
        'required source directory is missing: ${directory.path}',
      );
      continue;
    }
    final files =
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => _isHandwrittenDart(file.path))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final source = file.readAsStringSync();
      final relative = _normalized(file.absolute.path)
          .substring(_normalized(root.path).length + 1);
      diagnostics.addAll(
        checkClientSource(
          path: relative,
          source: source,
        ).map((diagnostic) => diagnostic.toString()),
      );
      checked++;
    }
  }
  if (checked == 0) {
    diagnostics.add('Client boundary check discovered no Dart source files');
  }
  if (diagnostics.isNotEmpty) {
    stderr.writeln(diagnostics.join('\n'));
    stderr.writeln(
      'Client boundary check failed (${diagnostics.length} errors)',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('Client boundary check passed ($checked source files)');
}

/// Parses one source file with exactly the rules used by verify-client.
/// Fixture tests call this entrypoint with forbidden Dart syntax, so a rule
/// cannot pass its own tests merely by matching a diagnostic message string.
List<ClientBoundaryDiagnostic> checkClientSource({
  required String path,
  required String source,
}) {
  path = _normalized(path);
  final parsed = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  );
  final diagnostics = <ClientBoundaryDiagnostic>[];
  void report(int offset, String rule, String message) {
    final location = parsed.lineInfo.getLocation(offset);
    diagnostics.add(
      ClientBoundaryDiagnostic(
        path: path,
        line: location.lineNumber,
        column: location.columnNumber,
        rule: rule,
        message: message,
      ),
    );
  }

  for (final error in parsed.errors) {
    report(error.offset, 'SYNTAX', error.message);
  }
  parsed.unit.accept(
    _BoundaryVisitor(
      path: path,
      source: source,
      report: report,
      isClient: path.startsWith('code/anywork_client/lib/'),
    ),
  );
  return List.unmodifiable(diagnostics);
}

final class ClientBoundaryDiagnostic {
  const ClientBoundaryDiagnostic({
    required this.path,
    required this.line,
    required this.column,
    required this.rule,
    required this.message,
  });
  final String path;
  final int line;
  final int column;
  final String rule;
  final String message;

  @override
  String toString() => '$path:$line:$column: [$rule] $message';
}

String _normalized(String path) => path.replaceAll('\\', '/');

bool _isHandwrittenDart(String path) {
  path = _normalized(path);
  return path.endsWith('.dart') &&
      !path.endsWith('.g.dart') &&
      !path.endsWith('.freezed.dart') &&
      !path.contains('/lib/src/rust/') &&
      !path.contains('/lib/l10n/app_localizations');
}

typedef _Report = void Function(int offset, String rule, String message);

final class _BoundaryVisitor extends RecursiveAstVisitor<void> {
  _BoundaryVisitor({
    required this.path,
    required this.source,
    required this.report,
    required this.isClient,
  });

  final String path;
  final String source;
  final _Report report;
  final bool isClient;
  final _classes = <ClassDeclaration>[];

  bool get isFeature => path.startsWith('code/anywork/lib/src/features/');
  bool get isProvider =>
      path.startsWith('code/anywork/lib/src/presentation/providers/');
  bool get isCommand =>
      path.contains('/commands/') || path.endsWith('_commands.dart');

  @override
  void visitImportDirective(ImportDirective node) {
    _checkUri(node.uri);
    for (final configuration in node.configurations) {
      _checkUri(configuration.uri);
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _checkUri(node.uri);
    for (final configuration in node.configurations) {
      _checkUri(configuration.uri);
    }
    super.visitExportDirective(node);
  }

  void _checkUri(StringLiteral literal) {
    final uri = literal.stringValue;
    if (uri == null) return;
    final resolved = Uri(path: path).resolve(uri).toString();
    if (isClient &&
        uri.startsWith('package:') &&
        !uri.startsWith('package:anywork_client/')) {
      report(
        literal.offset,
        'OWN-01',
        'Client may only import Dart SDK or itself: $uri',
      );
    }
    if (!isClient && uri.contains('package:anywork_client/src/')) {
      report(
        literal.offset,
        'OWN-01',
        'App must use the public Client API: $uri',
      );
    }
    if (isFeature &&
        (resolved.contains('/data/frb/') ||
            resolved.contains('/data/bridge/') ||
            resolved.contains('/infrastructure/') ||
            resolved.contains('/src/rust/') ||
            uri.startsWith('package:flutter_rust_bridge/') ||
            uri.endsWith('/transport_ports.dart') ||
            uri.endsWith('/studio_ports.dart'))) {
      report(
        literal.offset,
        'OWN-01',
        'Feature must use Client queries/actions, not transport: $uri',
      );
    }
  }

  @override
  void visitNamedType(NamedType node) {
    if (isClient &&
        const {'Ref', 'WidgetRef', 'BuildContext'}.contains(node.name.lexeme)) {
      report(
        node.offset,
        'OWN-01',
        'Client cannot depend on ${node.name.lexeme}',
      );
    }
    super.visitNamedType(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    _checkSharedVariables(node.variables);
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (node.isStatic) _checkSharedVariables(node.fields);
    super.visitFieldDeclaration(node);
  }

  void _checkSharedVariables(VariableDeclarationList variables) {
    if (variables.isConst) return;
    final declaredType = variables.type;
    for (final variable in variables.variables) {
      final initializer = variable.initializer;
      if (initializer is TypedLiteral && initializer.isConst ||
          initializer is InstanceCreationExpression && initializer.isConst) {
        continue;
      }
      final typeName = declaredType is NamedType
          ? declaredType.name.lexeme
          : '';
      final constructor = _constructorType(initializer);
      final isMap =
          typeName == 'Map' ||
          const {
            'Map',
            'HashMap',
            'LinkedHashMap',
            'SplayTreeMap',
          }.contains(constructor) ||
          initializer is SetOrMapLiteral &&
              (initializer.typeArguments?.arguments.length == 2 ||
                  initializer.elements.isEmpty ||
                  initializer.elements.any(
                    (element) => element is MapLiteralEntry,
                  ));
      final isBusiness = RegExp(
        r'(client|session|thread|channel|draft|operation|attempt|workspace|lane)',
        caseSensitive: false,
      ).hasMatch('${variable.name.lexeme} $typeName $constructor');
      if (isMap && (isClient || isBusiness)) {
        report(
          variable.offset,
          'LIFE-01',
          'Mutable Client/business maps must belong to an AppGraph instance',
        );
      }
      if (const {
            'StudioClient',
            'AnyworkClient',
            'AppGraph',
          }.contains(typeName) ||
          const {
            'StudioClient',
            'AnyworkClient',
            'AppGraph',
          }.contains(constructor)) {
        report(
          variable.offset,
          'LIFE-01',
          'Construct Client/AppGraph at the app composition root, not as a singleton',
        );
      }
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _classes.add(node);
    super.visitClassDeclaration(node);
    _classes.removeLast();
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (isProvider &&
        (node.target != null || node.isCascaded) &&
        const {
          'session',
          'composer',
          'skills',
          'sessionCosts',
        }.contains(name)) {
      report(
        node.offset,
        'LIFE-03',
        'Provider observation cannot admit a Client owner; observe existing owners created by logical demand',
      );
    }
    if (isCommand &&
        const {'readStudioState', '_reloadProduct'}.contains(name)) {
      report(
        node.offset,
        'CMD-02',
        'Command completion must observe typed owner frames/receipts, not reread aggregate StudioState',
      );
    }
    if (const {'onCancel', 'onResume', 'onDispose'}.contains(name) &&
        node.target?.toSource() == 'ref') {
      for (final argument in node.argumentList.arguments) {
        final calls = _LifecycleCalls();
        argument.accept(calls);
        final unsafeCalls = calls.names
            .where(_changesBusinessResource)
            .toList();
        final argumentSource = argument.toSource();
        if (unsafeCalls.isNotEmpty ||
            RegExp(r'clearHistory\s*:\s*true').hasMatch(argumentSource) ||
            (argument is! FunctionExpression &&
                _changesBusinessResource(argumentSource))) {
          report(
            argument.offset,
            'LIFE-02',
            'Provider lifecycle may only detach its own read-only observation',
          );
        }
      }
    }
    if (isFeature &&
        _classes.isNotEmpty &&
        const {'watch', 'read'}.contains(name) &&
        node.target?.toSource() == 'ref') {
      final owner = _classes.last;
      final className = owner.namePart.toSource().split(RegExp(r'[<(]')).first;
      final hasBusinessProps = RegExp(
        r'\b(?:required\s+)?this\.(?:threadId|sessionId|model|mode|effort|rows|snapshot|draft)\b',
      ).hasMatch(owner.toSource());
      final watchesBusiness = RegExp(
        r'(?:StoreProvider|CommandsProvider|DraftProvider|threadSessionStoreProvider|studioClientProvider)',
      ).hasMatch(node.argumentList.toSource());
      if (className.endsWith('View') && hasBusinessProps && watchesBusiness) {
        report(
          node.offset,
          'UI-01',
          'View with business props must not read a second business provider; move observation into a Connector',
        );
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (isFeature) {
      final type = node.constructorName.type.name.lexeme;
      if (type == 'UniqueKey' ||
          (const {'ValueKey', 'ObjectKey'}.contains(type) &&
              RegExp(
                r'(?:\bDateTime|\bRandom|\.text\b|\.content\b|hashCode|\.toString\()',
              ).hasMatch(node.argumentList.toSource()))) {
        report(
          node.offset,
          'UI-01',
          'Use stable domain identity for keys, not random/time/content values',
        );
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    if (node.body.statements.isEmpty) {
      final body = source.substring(node.body.offset, node.body.end);
      if (!body.contains('//') && !body.contains('/*')) {
        report(
          node.offset,
          'ERR-01',
          'Empty catch must explain why dropping this failure is safe',
        );
      }
    }
    super.visitCatchClause(node);
  }
}

String? _constructorType(Expression? expression) => switch (expression) {
  InstanceCreationExpression() => expression.constructorName.type.name.lexeme,
  MethodInvocation() when expression.target == null =>
    expression.methodName.name,
  _ => null,
};

bool _changesBusinessResource(String name) => RegExp(
  r'(?:close|dispose|clear|reset|delete|remove|releaseOrphans|releaseNewThreadOrphans|releaseAll|setDemand|openChatWindow|attachThread)',
  caseSensitive: false,
).hasMatch(name);

final class _LifecycleCalls extends RecursiveAstVisitor<void> {
  final names = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    names.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }
}
