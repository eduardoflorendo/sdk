// Copyright (c) 2015, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:io' as io;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/file_system.dart'
    show File, Folder, ResourceProvider, ResourceUriResolver;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/instrumentation/instrumentation.dart';
import 'package:analyzer/src/analysis_options/analysis_options_provider.dart';
import 'package:analyzer/src/context/builder.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/analysis/file_state.dart';
import 'package:analyzer/src/dart/analysis/performance_logger.dart';
import 'package:analyzer/src/dart/sdk/sdk.dart';
import 'package:analyzer/src/file_system/file_system.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer/src/lint/io.dart';
import 'package:analyzer/src/lint/linter.dart';
import 'package:analyzer/src/lint/project.dart';
import 'package:analyzer/src/lint/registry.dart';
import 'package:analyzer/src/services/lint.dart';
import 'package:analyzer/src/source/package_map_resolver.dart';
import 'package:analyzer/src/task/options.dart';
import 'package:analyzer/src/util/sdk.dart';
import 'package:package_config/packages.dart' show Packages;
import 'package:package_config/packages_file.dart' as pkgfile show parse;
import 'package:package_config/src/packages_impl.dart' show MapPackages;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

AnalysisOptionsProvider _optionsProvider = new AnalysisOptionsProvider();

Source createSource(Uri sourceUri) {
  return PhysicalResourceProvider.INSTANCE
      .getFile(sourceUri.toFilePath())
      .createSource(sourceUri);
}

/// Print the given message and exit with the given [exitCode]
void printAndFail(String message, {int exitCode: 15}) {
  print(message);
  io.exit(exitCode);
}

AnalysisOptions _buildAnalyzerOptions(LinterOptions options) {
  AnalysisOptionsImpl analysisOptions = new AnalysisOptionsImpl();
  if (options.analysisOptions != null) {
    YamlMap map =
        _optionsProvider.getOptionsFromString(options.analysisOptions);
    applyToAnalysisOptions(analysisOptions, map);
  }

  analysisOptions.hint = false;
  analysisOptions.lint = options.enableLints;
  analysisOptions.generateSdkErrors = options.showSdkWarnings;
  analysisOptions.enableTiming = options.enableTiming;
  analysisOptions.lintRules = options.enabledLints?.toList(growable: false);
  return analysisOptions;
}

class DriverOptions {
  /// The maximum number of sources for which AST structures should be kept
  /// in the cache.  The default is 512.
  int cacheSize = 512;

  /// The path to the dart SDK.
  String dartSdkPath;

  /// Whether to show lint warnings.
  bool enableLints = true;

  /// Whether to gather timing data during analysis.
  bool enableTiming = false;

  /// The path to a `.packages` configuration file
  String packageConfigPath;

  /// The path to the package root.
  String packageRootPath;

  /// Whether to show SDK warnings.
  bool showSdkWarnings = false;

  /// Whether to use Dart's Strong Mode analyzer.
  bool strongMode = true;

  /// The mock SDK (to speed up testing) or `null` to use the actual SDK.
  DartSdk mockSdk;

  /// Return `true` is the parser is able to parse asserts in the initializer
  /// list of a constructor.
  @deprecated
  bool get enableAssertInitializer => true;

  /// Set whether the parser is able to parse asserts in the initializer list of
  /// a constructor to match [enable].
  @deprecated
  void set enableAssertInitializer(bool enable) {
    // Ignored because the option is now always enabled.
  }

  /// Whether to use Dart 2.0 features.
  @deprecated
  bool get previewDart2 => true;

  @deprecated
  void set previewDart2(bool value) {}
}

class LintDriver {
  /// The sources which have been analyzed so far.  This is used to avoid
  /// analyzing a source more than once, and to compute the total number of
  /// sources analyzed for statistics.
  Set<Source> _sourcesAnalyzed = new HashSet<Source>();

  final LinterOptions options;

  LintDriver(this.options);

  /// Return the number of sources that have been analyzed so far.
  int get numSourcesAnalyzed => _sourcesAnalyzed.length;

  List<UriResolver> get resolvers {
    // TODO(brianwilkerson) Use the context builder to compute all of the resolvers.
    ResourceProvider resourceProvider = PhysicalResourceProvider.INSTANCE;
    ContextBuilder builder = new ContextBuilder(resourceProvider, null, null);

    DartSdk sdk = options.mockSdk ??
        new FolderBasedDartSdk(
            resourceProvider, resourceProvider.getFolder(sdkDir));

    List<UriResolver> resolvers = [new DartUriResolver(sdk)];

    if (options.packageRootPath != null) {
      // TODO(brianwilkerson) After 0.30.0 is published, clean up the following.
      try {
        // Try to use the post 0.30.0 API.
        (builder as dynamic).builderOptions.defaultPackagesDirectoryPath =
            options.packageRootPath;
      } catch (_) {
        // If that fails, fall back to the pre 0.30.0 API.
        (builder as dynamic).defaultPackagesDirectoryPath =
            options.packageRootPath;
      }
      Map<String, List<Folder>> packageMap =
          builder.convertPackagesToMap(builder.createPackageMap(null));
      resolvers.add(new PackageMapUriResolver(resourceProvider, packageMap));
    }

    // File URI resolver must come last so that files inside "/lib" are
    // are analyzed via "package:" URI's.
    resolvers.add(new ResourceUriResolver(resourceProvider));
    return resolvers;
  }

  ResourceProvider get resourceProvider => options.resourceProvider;

  String get sdkDir {
    // In case no SDK has been specified, fall back to inferring it.
    return options.dartSdkPath ?? getSdkPath();
  }

  Future<List<AnalysisErrorInfo>> analyze(Iterable<io.File> files) async {
    // TODO(brianwilkerson) Determine whether this await is necessary.
    await null;
    AnalysisEngine.instance.instrumentationService = new StdInstrumentation();

    SourceFactory sourceFactory =
        new SourceFactory(resolvers, _getPackageConfig());

    PerformanceLog log = new PerformanceLog(null);
    AnalysisDriverScheduler scheduler = new AnalysisDriverScheduler(log);
    AnalysisDriver analysisDriver = new AnalysisDriver(
        scheduler,
        log,
        resourceProvider,
        new MemoryByteStore(),
        new FileContentOverlay(),
        null,
        sourceFactory,
        _buildAnalyzerOptions(options));
    analysisDriver.results.listen((_) {});
    analysisDriver.exceptions.listen((_) {});
    scheduler.start();

    List<Source> sources = [];
    for (io.File file in files) {
      File sourceFile =
          resourceProvider.getFile(p.normalize(file.absolute.path));
      Source source = sourceFile.createSource();
      Uri uri = sourceFactory.restoreUri(source);
      if (uri != null) {
        // Ensure that we analyze the file using its canonical URI (e.g. if
        // it's in "/lib", analyze it using a "package:" URI).
        source = sourceFile.createSource(uri);
      }

      sources.add(source);
      analysisDriver.addFile(source.fullName);
    }

    DartProject project = await DartProject.create(analysisDriver, sources);
    Registry.ruleRegistry.forEach((lint) {
      if (lint is ProjectVisitor) {
        (lint as ProjectVisitor).visit(project);
      }
    });

    List<AnalysisErrorInfo> errors = [];
    for (Source source in sources) {
      ErrorsResult errorsResult =
          await analysisDriver.getErrors(source.fullName);
      errors.add(new AnalysisErrorInfoImpl(
          errorsResult.errors, errorsResult.lineInfo));
      _sourcesAnalyzed.add(source);
    }

    return errors;
  }

  void registerLinters(AnalysisContext context) {
    if (options.enableLints) {
      setLints(context, options.enabledLints?.toList(growable: false));
    }
  }

  Packages _getPackageConfig() {
    if (options.packageConfigPath != null) {
      String packageConfigPath = options.packageConfigPath;
      Uri fileUri = new Uri.file(packageConfigPath);
      try {
        io.File configFile = new io.File.fromUri(fileUri).absolute;
        List<int> bytes = configFile.readAsBytesSync();
        Map<String, Uri> map = pkgfile.parse(bytes, configFile.uri);
        return new MapPackages(map);
      } catch (e) {
        printAndFail(
            'Unable to read package config data from $packageConfigPath: $e');
      }
    }
    return null;
  }
}

/// Prints logging information comments to the [outSink] and error messages to
/// [errorSink].
class StdInstrumentation extends InstrumentationService {
  StdInstrumentation() : super(null);

  @override
  void logError(String message, [exception]) {
    errorSink.writeln(message);
    if (exception != null) {
      errorSink.writeln(exception);
    }
  }

  @override
  void logException(dynamic exception, [StackTrace stackTrace]) {
    errorSink.writeln(exception);
    errorSink.writeln(stackTrace);
  }

  @override
  void logInfo(String message, [exception]) {
    outSink.writeln(message);
    if (exception != null) {
      outSink.writeln(exception);
    }
  }
}
