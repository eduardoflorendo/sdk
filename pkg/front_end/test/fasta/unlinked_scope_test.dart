// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/messages/diagnostic_message.dart'
    show DiagnosticMessage, DiagnosticMessageHandler;

import 'package:_fe_analyzer_shared/src/parser/parser.dart' show Parser;

import 'package:_fe_analyzer_shared/src/scanner/scanner.dart'
    show Token, scanString;

import 'package:expect/expect.dart' show Expect;

import 'package:kernel/ast.dart' show Expression, ProcedureKind;

import 'package:kernel/target/targets.dart' show NoneTarget, TargetFlags;

import 'package:front_end/src/api_prototype/compiler_options.dart'
    show CompilerOptions;

import 'package:front_end/src/base/processed_options.dart'
    show ProcessedOptions;

import 'package:front_end/src/fasta/builder/procedure_builder.dart';

import 'package:front_end/src/fasta/compiler_context.dart' show CompilerContext;

import 'package:front_end/src/fasta/dill/dill_target.dart' show DillTarget;

import 'package:front_end/src/fasta/kernel/body_builder.dart' show BodyBuilder;

import 'package:front_end/src/fasta/kernel/kernel_target.dart'
    show KernelTarget;

import 'package:front_end/src/fasta/kernel/unlinked_scope.dart'
    show UnlinkedScope;

import 'package:front_end/src/fasta/scope.dart' show Scope;

import 'package:front_end/src/fasta/source/source_library_builder.dart'
    show SourceLibraryBuilder;

DiagnosticMessageHandler handler;

class MockLibraryBuilder extends SourceLibraryBuilder {
  MockLibraryBuilder(Uri uri)
      : super(
            uri,
            uri,
            new KernelTarget(
                    null,
                    false,
                    new DillTarget(
                        null, null, new NoneTarget(new TargetFlags())),
                    null)
                .loader,
            null);

  ProcedureBuilder mockProcedure(String name) {
    return new ProcedureBuilderImpl(null, 0, null, name, null, null,
        ProcedureKind.Getter, this, -1, -1, -1, -1);
  }
}

class MockBodyBuilder extends BodyBuilder {
  MockBodyBuilder.internal(
      MockLibraryBuilder libraryBuilder, String name, Scope scope)
      : super(
            libraryBuilder: libraryBuilder,
            member: libraryBuilder.mockProcedure(name),
            enclosingScope: scope,
            formalParameterScope: scope,
            isDeclarationInstanceMember: false,
            uri: libraryBuilder.uri);

  MockBodyBuilder(Uri uri, String name, Scope scope)
      : this.internal(new MockLibraryBuilder(uri), name, scope);
}

Expression compileExpression(String source) {
  BodyBuilder listener = new MockBodyBuilder(
      Uri.parse("org-dartlang-test:my_library.dart"),
      "<test>",
      new UnlinkedScope());

  handler = (DiagnosticMessage message) {
    throw message.plainTextFormatted.join("\n");
  };

  Token token = scanString(source).tokens;
  Parser parser = new Parser(listener);
  parser.parseExpression(parser.syntheticPreviousToken(token));
  Expression e = listener.popForValue();
  listener.checkEmpty(-1);
  return e;
}

void testExpression(String source, [String expected]) {
  Expression e = compileExpression(source);
  String actual =
      "$e".replaceAll(new RegExp(r'invalid-expression "[^"]*"\.'), "");
  Expect.stringEquals(expected ?? source, actual);
  print(e);
}

main() {
  CompilerContext context = new CompilerContext(new ProcessedOptions(
      options: new CompilerOptions()
        ..onDiagnostic = (DiagnosticMessage message) {
          handler(message);
        }));
  context.runInContext((_) {
    testExpression("unresolved");
    testExpression("a + b", "a.+(b)");
    testExpression("a = b");
    return Future<void>.value();
  });
}
