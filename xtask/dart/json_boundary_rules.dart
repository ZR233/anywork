import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Known protocols stay typed. Only the approved artifact presentation helper
/// interprets deliberately open JSON, directly from OpaqueArtifactJson.json.
/// Syntax checks complement, not replace, that helper's behavioral regression.
void checkJsonBoundaries({
  required CompilationUnit unit,
  required String path,
  required void Function(int offset, String rule, String message) report,
}) {
  if (!path.startsWith('code/anywork_client/lib/') &&
      !path.startsWith('code/anywork/lib/src/features/') &&
      !path.startsWith('code/anywork/lib/src/infrastructure/') &&
      !path.startsWith('code/anywork/lib/src/diagnostics/')) return;
  unit.accept(_JsonBoundaryVisitor(path, report));
}

final class _JsonBoundaryVisitor extends RecursiveAstVisitor<void> {
  _JsonBoundaryVisitor(this.path, this.report);
  final String path;
  final void Function(int, String, String) report;
  final _values = <Set<String>>[{}];
  final _collections = <Set<String>>[{}];

  bool get _artifactHelper => path ==
      'code/anywork/lib/src/features/conversation/presentation/artifact_links.dart';

  void _reject(AstNode node) => report(node.offset, 'JSON-01',
      'Decode only explicit OpaqueArtifactJson.json in the approved artifact helper; known DTOs stay typed');

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final values = {..._values.last};
    final collections = {..._collections.last};
    for (final parameter in node.functionExpression.parameters?.parameters ??
        const <FormalParameter>[]) {
      // Inspect the printed type of an AST formal, not comments or strings.
      // Untyped/dynamic inputs never acquire the opaque exception.
      final formal = parameter is DefaultFormalParameter ? parameter.parameter : parameter;
      final source = formal.toSource();
      final name = RegExp(r'(\w+)$').firstMatch(source)?.group(1);
      values.remove(name);
      collections.remove(name);
      final value = RegExp(r'^(?:required\s+)?OpaqueArtifactJson\s+(\w+)$').firstMatch(source);
      final collection = RegExp(r'^(?:required\s+)?(?:Iterable|List)<OpaqueArtifactJson>\s+(\w+)$').firstMatch(source);
      if (value != null) values.add(value.group(1)!);
      if (collection != null) collections.add(collection.group(1)!);
    }
    _values.add(values);
    _collections.add(collections);
    super.visitFunctionDeclaration(node);
    _values.removeLast();
    _collections.removeLast();
  }

  @override
  void visitBlock(Block node) {
    _values.add({..._values.last});
    _collections.add({..._collections.last});
    super.visitBlock(node);
    _values.removeLast();
    _collections.removeLast();
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final name = node.name.lexeme;
    _values.last.remove(name);
    _collections.last.remove(name);
    final parent = node.parent;
    final type = parent is VariableDeclarationList ? parent.type?.toSource() : null;
    if (type == 'OpaqueArtifactJson') _values.last.add(name);
    if (type == 'Iterable<OpaqueArtifactJson>' || type == 'List<OpaqueArtifactJson>') {
      _collections.last.add(name);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    final values = {..._values.last};
    final loop = RegExp(r'^(?:final|OpaqueArtifactJson)\s+(\w+)\s+in\s+(\w+)$')
        .firstMatch(node.forLoopParts.toSource());
    if (loop != null && _collections.last.contains(loop.group(2))) values.add(loop.group(1)!);
    _values.add(values);
    super.visitForStatement(node);
    _values.removeLast();
  }

  bool _opaqueArgument(ArgumentList arguments) {
    if (!_artifactHelper || arguments.arguments.length != 1) return false;
    final input = arguments.arguments.single;
    if (input is! PropertyAccess && input is! PrefixedIdentifier) return false;
    final match = RegExp(r'^(\w+)\.json$').firstMatch(input.toSource());
    return match != null && _values.last.contains(match.group(1));
  }

  bool _directConversion(AstNode? parent) => parent is MethodInvocation &&
      const {'convert', 'decode'}.contains(parent.methodName.name) &&
      _opaqueArgument(parent.argumentList);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final target = node.target?.toSource() ?? '';
    final isDecode = name == 'jsonDecode' ||
        name == 'decode' && (target == 'json' || target.endsWith('.json'));
    if (isDecode && !_opaqueArgument(node.argumentList)) _reject(node);
    if (const {'JsonDecoder', 'JsonCodec'}.contains(name) && !_directConversion(node.parent)) {
      _reject(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (const {'JsonDecoder', 'JsonCodec'}.contains(node.name.lexeme)) {
      final creation = node.parent?.parent;
      if (creation is! InstanceCreationExpression || !_directConversion(creation.parent)) _reject(node);
    }
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'jsonDecode') {
      final parent = node.parent;
      if (parent is ShowCombinator || parent is HideCombinator) return;
      if (parent is! MethodInvocation || parent.methodName != node) _reject(node);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name == 'decode' && node.prefix.name == 'json') _reject(node);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name == 'decode' && (node.target?.toSource().endsWith('.json') ?? false)) {
      _reject(node);
    }
    super.visitPropertyAccess(node);
  }
}
