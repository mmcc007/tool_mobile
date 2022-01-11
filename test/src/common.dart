// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//import 'dart:async';

//import 'package:args/command_runner.dart';
//import 'package:test_api/test_api.dart' hide TypeMatcher, isInstanceOf;
//import 'package:test_api/test_api.dart' as test_package show TypeMatcher;
import 'package:test/test.dart' hide TypeMatcher, isInstanceOf;
import 'package:test/test.dart' as test_package show TypeMatcher;
import 'package:tool_base/tool_base.dart';

//import 'package:flutter_tools/src/base/common.dart';
//import 'package:flutter_tools/src/base/file_system.dart';
//import 'package:flutter_tools/src/base/platform.dart';
//import 'package:flutter_tools/src/base/process.dart';
//import 'package:flutter_tools/src/commands/create.dart';
//import 'package:flutter_tools/src/runner/flutter_command.dart';
//import 'package:flutter_tools/src/runner/flutter_command_runner.dart';

//export 'package:test_api/test_api.dart' hide TypeMatcher, isInstanceOf; // Defines a 'package:test' shim.
export 'package:test/test.dart'
    hide TypeMatcher, isInstanceOf; // Defines a 'package:test' shim.

/// A matcher that compares the type of the actual value to the type argument T.
// TODO(ianh): Remove this once https://github.com/dart-lang/matcher/issues/98 is fixed
Matcher isInstanceOf<T>() => test_package.TypeMatcher<T>();

//CommandRunner<void> createTestCommandRunner([ FlutterCommand command ]) {
//  final FlutterCommandRunner runner = FlutterCommandRunner();
//  if (command != null)
//    runner.addCommand(command);
//  return runner;
//}

/// Updates [path] to have a modification time [seconds] from now.
void updateFileModificationTime(
  String path,
  DateTime baseTime,
  int seconds,
) {
  final DateTime modificationTime = baseTime.add(Duration(seconds: seconds));
  fs.file(path).setLastModifiedSync(modificationTime);
}

/// Matcher for functions that throw [ToolExit].
Matcher throwsToolExit({int exitCode, Pattern message}) {
  Matcher matcher = isToolExit;
  if (exitCode != null)
    matcher = allOf(matcher, (ToolExit e) => e.exitCode == exitCode);
  if (message != null)
    matcher = allOf(matcher, (ToolExit e) => e.message.contains(message));
  return throwsA(matcher);
}

/// Matcher for [ToolExit]s.
final Matcher isToolExit = isInstanceOf<ToolExit>();

/// Matcher for functions that throw [ProcessExit].
Matcher throwsProcessExit([dynamic exitCode]) {
  return exitCode == null
      ? throwsA(isProcessExit)
      : throwsA(
          allOf(isProcessExit, (ProcessExit e) => e.exitCode == exitCode));
}

/// Matcher for [ProcessExit]s.
final Matcher isProcessExit = isInstanceOf<ProcessExit>();

///// Creates a flutter project in the [temp] directory using the
///// [arguments] list if specified, or `--no-pub` if not.
///// Returns the path to the flutter project.
//Future<String> createProject(Directory temp, { List<String> arguments }) async {
//  arguments ??= <String>['--no-pub'];
//  final String projectPath = fs.path.join(temp.path, 'flutter_project');
//  final CreateCommand command = CreateCommand();
//  final CommandRunner<void> runner = createTestCommandRunner(command);
//  await runner.run(<String>['create']..addAll(arguments)..add(projectPath));
//  return projectPath;
//}

/// Test case timeout for tests involving remote calls to `pub get` or similar.
const Timeout allowForRemotePubInvocation = Timeout.factor(10.0);

/// Test case timeout for tests involving creating a Flutter project with
/// `--no-pub`. Use [allowForRemotePubInvocation] when creation involves `pub`.
const Timeout allowForCreateFlutterProject = Timeout.factor(3.0);
