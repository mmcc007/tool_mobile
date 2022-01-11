// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:tool_base/tool_base.dart';

//import '../base/common.dart';
//import '../base/context.dart';
//import '../base/file_system.dart';
//import '../base/io.dart' show ProcessResult;
//import '../base/os.dart';
//import '../base/platform.dart';
//import '../base/process.dart';
//import '../base/process_manager.dart';
//import '../base/version.dart';
//import '../convert.dart';
//import '../globals.dart';
//import 'android_studio.dart' as android_studio;

AndroidSdk get androidSdk => context.get<AndroidSdk>()!;

const String kAndroidHome = 'ANDROID_HOME';
const String kAndroidSdkRoot = 'ANDROID_SDK_ROOT';

// Android SDK layout:

// $ANDROID_HOME/platform-tools/adb

// $ANDROID_HOME/build-tools/19.1.0/aapt, dx, zipalign
// $ANDROID_HOME/build-tools/22.0.1/aapt
// $ANDROID_HOME/build-tools/23.0.2/aapt
// $ANDROID_HOME/build-tools/24.0.0-preview/aapt
// $ANDROID_HOME/build-tools/25.0.2/apksigner

// $ANDROID_HOME/platforms/android-22/android.jar
// $ANDROID_HOME/platforms/android-23/android.jar
// $ANDROID_HOME/platforms/android-N/android.jar

final RegExp _numberedAndroidPlatformRe = RegExp(r'^android-([0-9]+)$');
final RegExp _sdkVersionRe = RegExp(r'^ro.build.version.sdk=([0-9]+)$');

/// The minimum Android SDK version we support.
const int minimumAndroidSdkVersion = 25;

/// Locate ADB. Prefer to use one from an Android SDK, if we can locate that.
/// This should be used over accessing androidSdk.adbPath directly because it
/// will work for those users who have Android Platform Tools installed but
/// not the full SDK.
String getAdbPath([AndroidSdk? existingSdk]) {
  var adbPath = existingSdk?.adbPath;
  if (adbPath != null) {
    return adbPath;
  }

  final sdk = AndroidSdk.locateAndroidSdk();

  adbPath = sdk?.latestVersion == null ? os.which('adb')?.path : sdk?.adbPath;

  if (adbPath != null) {
    return adbPath;
  }

  return throw ToolExit('Could not find "abd"');
}

/// Locate 'emulator'. Prefer to use one from an Android SDK, if we can locate that.
/// This should be used over accessing androidSdk.emulatorPath directly because it
/// will work for those users who have Android Tools installed but
/// not the full SDK.
String? getEmulatorPath([AndroidSdk? existingSdk]) {
  return existingSdk?.emulatorPath ??
      AndroidSdk.locateAndroidSdk()?.emulatorPath;
}

/// Locate the path for storing AVD emulator images. Returns null if none found.
String? getAvdPath() {
  final avdHome = platform.environment['ANDROID_AVD_HOME'];
  final List<String> searchPaths = <String>[if (avdHome != null) avdHome];

  final home = platform.environment['HOME'];
  if (home != null)
    searchPaths
        .add(fs.path.join(home, '.android', 'avd'));

  if (platform.isWindows) {
    final homeDrive = platform.environment['HOMEDRIVE'];
    final homePath = platform.environment['HOMEPATH'];

    if (homeDrive != null && homePath != null) {
      // Can't use path.join for HOMEDRIVE/HOMEPATH
      // https://github.com/dart-lang/path/issues/37
      final String home = homeDrive + homePath;
      searchPaths.add(fs.path.join(home, '.android', 'avd'));
    }
  }

  return searchPaths.firstWhereOrNull(
        (String p) => fs.directory(p).existsSync(),
      );
}

/// Locate 'avdmanager'. Prefer to use one from an Android SDK, if we can locate that.
/// This should be used over accessing androidSdk.avdManagerPath directly because it
/// will work for those users who have Android Tools installed but
/// not the full SDK.
String? getAvdManagerPath([AndroidSdk? existingSdk]) {
  return existingSdk?.avdManagerPath ??
      AndroidSdk.locateAndroidSdk()?.avdManagerPath;
}

class AndroidNdkSearchError {
  AndroidNdkSearchError(this.reason);

  /// The message explaining why NDK was not found.
  final String reason;
}

class AndroidNdk {
  AndroidNdk._(this.directory, this.compiler, this.compilerArgs);

  /// The path to the NDK.
  final String directory;

  /// The path to the NDK compiler.
  final String compiler;

  /// The mandatory arguments to the NDK compiler.
  final List<String> compilerArgs;

  /// Locate NDK within the given SDK or throw [AndroidNdkSearchError].
  static AndroidNdk locateNdk(String androidHomeDir) {
    if (androidHomeDir == null) {
      throw AndroidNdkSearchError('Can not locate NDK because no SDK is found');
    }

    String findBundle(String androidHomeDir) {
      final String ndkDirectory = fs.path.join(androidHomeDir, 'ndk-bundle');
      if (!fs.isDirectorySync(ndkDirectory)) {
        throw AndroidNdkSearchError(
            'Can not locate ndk-bundle, tried: $ndkDirectory');
      }
      return ndkDirectory;
    }

    // Returns list that contains toolchain bin folder and compiler binary name.
    List<String> findToolchainAndCompiler(String ndkDirectory) {
      String directory;
      if (platform.isLinux) {
        directory = 'linux-x86_64';
      } else if (platform.isMacOS) {
        directory = 'darwin-x86_64';
      } else {
        throw AndroidNdkSearchError('Only Linux and macOS are supported');
      }

      final String toolchainBin = fs.path.join(ndkDirectory, 'toolchains',
          'arm-linux-androideabi-4.9', 'prebuilt', directory, 'bin');
      final String ndkCompiler =
          fs.path.join(toolchainBin, 'arm-linux-androideabi-gcc');
      if (!fs.isFileSync(ndkCompiler)) {
        throw AndroidNdkSearchError(
            'Can not locate GCC binary, tried $ndkCompiler');
      }

      return <String>[toolchainBin, ndkCompiler];
    }

    List<String> findSysroot(String ndkDirectory) {
      // If entity represents directory with name android-<version> that
      // contains arch-arm subdirectory then returns version, otherwise
      // returns null.
      int? toPlatformVersion(FileSystemEntity entry) {
        if (entry is! Directory) {
          return null;
        }

        if (!fs.isDirectorySync(fs.path.join(entry.path, 'arch-arm'))) {
          return null;
        }

        final String name = fs.path.basename(entry.path);

        const String platformPrefix = 'android-';
        if (!name.startsWith(platformPrefix)) {
          return null;
        }

        return int.tryParse(name.substring(platformPrefix.length));
      }

      final String platformsDir = fs.path.join(ndkDirectory, 'platforms');
      final List<int> versions = fs
          .directory(platformsDir)
          .listSync()
          .map(toPlatformVersion)
          .whereNotNull()
          .toList(growable: false);
      versions.sort();

      final suitableVersion = versions
          .firstWhereOrNull((int version) => version >= 9);
      if (suitableVersion == null) {
        throw AndroidNdkSearchError(
            'Can not locate a suitable platform ARM sysroot (need android-9 or newer), tried to look in $platformsDir');
      }

      final String armPlatform = fs.path.join(
          ndkDirectory, 'platforms', 'android-$suitableVersion', 'arch-arm');
      return <String>['--sysroot', armPlatform];
    }

    int findNdkMajorVersion(String ndkDirectory) {
      final String propertiesFile =
          fs.path.join(ndkDirectory, 'source.properties');
      if (!fs.isFileSync(propertiesFile)) {
        throw AndroidNdkSearchError(
            'Can not establish ndk-bundle version: $propertiesFile not found');
      }

      // Parse source.properties: each line has Key = Value format.
      final Iterable<String> propertiesFileLines = fs
          .file(propertiesFile)
          .readAsStringSync()
          .split('\n')
          .map<String>((String line) => line.trim())
          .where((String line) => line.isNotEmpty);
      final Map<String, String> properties = <String, String>{};
      for (String line in propertiesFileLines) {
        final List<String> parts = line.split(' = ');
        if (parts.length == 2) {
          properties[parts[0]] = parts[1];
        } else {
          printError('Malformed line in ndk source.properties: "$line".');
        }
      }

      final pkgRevision = properties['Pkg.Revision'];
      if (pkgRevision == null) {
        throw AndroidNdkSearchError(
            'Can not establish ndk-bundle version: $propertiesFile does not contain Pkg.Revision');
      }

      // Extract major version from Pkg.Revision property which looks like <ndk-version>.x.y.
      return int.parse(pkgRevision.split('.').first);
    }

    final String ndkDir = findBundle(androidHomeDir);
    final int ndkVersion = findNdkMajorVersion(ndkDir);
    final List<String> ndkToolchainAndCompiler =
        findToolchainAndCompiler(ndkDir);
    final String ndkToolchain = ndkToolchainAndCompiler[0];
    final String ndkCompiler = ndkToolchainAndCompiler[1];
    final List<String> ndkCompilerArgs = findSysroot(ndkDir);
    if (ndkVersion >= 18) {
      // Newer versions of NDK use clang instead of gcc, which falls back to
      // system linker instead of using toolchain linker. Force clang to
      // use appropriate linker by passing -fuse-ld=<path-to-ld> command line
      // flag.
      final String ndkLinker =
          fs.path.join(ndkToolchain, 'arm-linux-androideabi-ld');
      if (!fs.isFileSync(ndkLinker)) {
        throw AndroidNdkSearchError(
            'Can not locate linker binary, tried $ndkLinker');
      }
      ndkCompilerArgs.add('-fuse-ld=$ndkLinker');
    }
    return AndroidNdk._(ndkDir, ndkCompiler, ndkCompilerArgs);
  }

  /// Returns a descriptive message explaining why NDK can not be found within
  /// the given SDK.
  static String explainMissingNdk(String androidHomeDir) {
    try {
      locateNdk(androidHomeDir);
      return 'Unexpected error: found NDK on the second try';
    } on AndroidNdkSearchError catch (e) {
      return e.reason;
    }
  }
}

class AndroidSdk {
  AndroidSdk(this.directory, [this.ndk]) {
    reinitialize();
  }

  static const String _javaHomeEnvironmentVariable = 'JAVA_HOME';
  static const String _javaExecutable = 'java';

  /// The path to the Android SDK.
  final String directory;

  /// Android NDK.
  final AndroidNdk? ndk;

  List<AndroidSdkVersion>? _sdkVersions;
  AndroidSdkVersion? _latestVersion;

  /// Whether the `platform-tools` directory exists in the Android SDK.
  ///
  /// It is possible to have an Android SDK folder that is missing this with
  /// the expectation that it will be downloaded later, e.g. by gradle or the
  /// sdkmanager. The [licensesAvailable] property should be used to determine
  /// whether the licenses are at least possibly accepted.
  bool get platformToolsAvailable =>
      fs.directory(fs.path.join(directory, 'platform-tools')).existsSync();

  /// Whether the `licenses` directory exists in the Android SDK.
  ///
  /// The existence of this folder normally indicates that the SDK licenses have
  /// been accepted, e.g. via the sdkmanager, Android Studio, or by copying them
  /// from another workstation such as in CI scenarios. If these files are valid
  /// gradle or the sdkmanager will be able to download and use other parts of
  /// the SDK on demand.
  bool get licensesAvailable =>
      fs.directory(fs.path.join(directory, 'licenses')).existsSync();

  static AndroidSdk? locateAndroidSdk() {
    String? findAndroidHomeDir() {
      var androidHomeDir = config.getValue('android-sdk') as String?
          ?? platform.environment[kAndroidHome]
          ?? platform.environment[kAndroidSdkRoot];

      final home = homeDirPath;
      if (androidHomeDir == null && home != null) {
        if (platform.isLinux) {
          androidHomeDir = fs.path.join(home, 'Android', 'Sdk');
        } else if (platform.isMacOS) {
          androidHomeDir =
              fs.path.join(home, 'Library', 'Android', 'sdk');
        } else if (platform.isWindows) {
          androidHomeDir =
              fs.path.join(home, 'AppData', 'Local', 'Android', 'sdk');
        }
      }

      if (androidHomeDir != null) {
        if (validSdkDirectory(androidHomeDir)) return androidHomeDir;
        if (validSdkDirectory(fs.path.join(androidHomeDir, 'sdk')))
          return fs.path.join(androidHomeDir, 'sdk');
      }

      // in build-tools/$version/aapt
      final List<File> aaptBins = os.whichAll('aapt');
      for (File aaptBin in aaptBins) {
        // Make sure we're using the aapt from the SDK.
        aaptBin = fs.file(aaptBin.resolveSymbolicLinksSync());
        final String dir = aaptBin.parent.parent.parent.path;
        if (validSdkDirectory(dir)) return dir;
      }

      // in platform-tools/adb
      final List<File> adbBins = os.whichAll('adb');
      for (File adbBin in adbBins) {
        // Make sure we're using the adb from the SDK.
        adbBin = fs.file(adbBin.resolveSymbolicLinksSync());
        final String dir = adbBin.parent.parent.path;
        if (validSdkDirectory(dir)) return dir;
      }

      return null;
    }

    final androidHomeDir = findAndroidHomeDir();
    if (androidHomeDir == null) {
      // No dice.
      printTrace('Unable to locate an Android SDK.');
      return null;
    }

    // Try to find the NDK compiler. If we can't find it, it's also ok.
    AndroidNdk? ndk;
    try {
      ndk = AndroidNdk.locateNdk(androidHomeDir);
    } on AndroidNdkSearchError {
      // Ignore AndroidNdkSearchError's but don't ignore any other
      // exceptions.
    }

    return AndroidSdk(androidHomeDir, ndk);
  }

  static bool validSdkDirectory(String dir) {
    return sdkDirectoryHasLicenses(dir) || sdkDirectoryHasPlatformTools(dir);
  }

  static bool sdkDirectoryHasPlatformTools(String dir) {
    return fs.isDirectorySync(fs.path.join(dir, 'platform-tools'));
  }

  static bool sdkDirectoryHasLicenses(String dir) {
    return fs.isDirectorySync(fs.path.join(dir, 'licenses'));
  }

  List<AndroidSdkVersion> get sdkVersions => _sdkVersions!;

  AndroidSdkVersion get latestVersion => _latestVersion!;

  String? get adbPath =>
      getPlatformToolsPath(platform.isWindows ? 'adb.exe' : 'adb');

  String? get emulatorPath => getEmulatorPath();

  String? get avdManagerPath => getAvdManagerPath();

  Directory get _platformsDir =>
      fs.directory(fs.path.join(directory, 'platforms'));

  Iterable<Directory> get _platforms {
    Iterable<Directory> platforms = <Directory>[];
    if (_platformsDir.existsSync()) {
      platforms = _platformsDir.listSync().whereType<Directory>();
    }
    return platforms;
  }

  /// Validate the Android SDK. This returns an empty list if there are no
  /// issues; otherwise, it returns a list of issues found.
  List<String> validateSdkWellFormed() {
    if (adbPath == null || !processManager.canRun(adbPath))
      return <String>['Android SDK file not found: ${adbPath ?? 'adb'}.'];

    if (sdkVersions.isEmpty || latestVersion == null) {
      final StringBuffer msg = StringBuffer(
          'No valid Android SDK platforms found in ${_platformsDir.path}.');
      if (_platforms.isEmpty) {
        msg.write(' Directory was empty.');
      } else {
        msg.write(' Candidates were:\n');
        msg.write(_platforms
            .map((Directory dir) => '  - ${dir.basename}')
            .join('\n'));
      }
      return <String>[msg.toString()];
    }

    return latestVersion.validateSdkWellFormed();
  }

  String? getPlatformToolsPath(String binaryName) {
    final String path = fs.path.join(directory, 'platform-tools', binaryName);
    if (fs.file(path).existsSync()) return path;
    return null;
  }

  String? getEmulatorPath() {
    final String binaryName = platform.isWindows ? 'emulator.exe' : 'emulator';
    // Emulator now lives inside "emulator" but used to live inside "tools" so
    // try both.
    final List<String> searchFolders = <String>['emulator', 'tools'];
    for (final String folder in searchFolders) {
      final String path = fs.path.join(directory, folder, binaryName);
      if (fs.file(path).existsSync()) return path;
    }
    return null;
  }

  String? getAvdManagerPath() {
    final binaryName = platform.isWindows ? 'avdmanager.bat' : 'avdmanager';
    final path = fs.path.join(directory, 'tools', 'bin', binaryName);
    return fs.file(path).existsSync() ? path : null;
  }

  /// Sets up various paths used internally.
  ///
  /// This method should be called in a case where the tooling may have updated
  /// SDK artifacts, such as after running a gradle build.
  void reinitialize() {
    List<Version> buildTools = <Version>[]; // 19.1.0, 22.0.1, ...

    final Directory buildToolsDir =
        fs.directory(fs.path.join(directory, 'build-tools'));
    if (buildToolsDir.existsSync()) {
      buildTools = buildToolsDir
          .listSync()
          .map((FileSystemEntity entity) {
            try {
              return Version.parse(entity.basename);
            } catch (error) {
              return null;
            }
          })
          .whereNotNull()
          .toList();
    }

    // Match up platforms with the best corresponding build-tools.
    _sdkVersions = _platforms
        .map((Directory platformDir) {
          final String platformName = platformDir.basename;
          int platformVersion;

          try {
            final v =
                _numberedAndroidPlatformRe.firstMatch(platformName)?.group(1);
            if (v != null) {
              platformVersion = int.parse(v);
            } else {
              final String buildProps =
                  platformDir.childFile('build.prop').readAsStringSync();
              final versionString = const LineSplitter()
                  .convert(buildProps)
                  .map((s) => _sdkVersionRe.firstMatch(s)?.group(1))
                  .whereNotNull()
                  .first;
              platformVersion = int.parse(versionString);
            }
          } catch (error) {
            return null;
          }

          var buildToolsVersion =
              Version.primary(buildTools.where((Version version) {
            return version.major == platformVersion;
          }).toList());

          buildToolsVersion ??= Version.primary(buildTools);

          if (buildToolsVersion == null) return null;

          return AndroidSdkVersion._(
            this,
            sdkLevel: platformVersion,
            platformName: platformName,
            buildToolsVersion: buildToolsVersion,
          );
        })
        .whereNotNull()
        .toList();

    _sdkVersions?.sort();

    _latestVersion = _sdkVersions?.lastOrNull;
  }

  /// Returns the filesystem path of the Android SDK manager tool or null if not found.
  String get sdkManagerPath {
    return fs.path.join(directory, 'tools', 'bin', 'sdkmanager');
  }

  /// First try Java bundled with Android Studio, then sniff JAVA_HOME, then fallback to PATH.
  static String? findJavaBinary() {
//    if (android_studio.javaPath != null)
//      return fs.path.join(android_studio.javaPath, 'bin', 'java');

    final javaHomeEnv =
        platform.environment[_javaHomeEnvironmentVariable];
    if (javaHomeEnv != null) {
      // Trust JAVA_HOME.
      return fs.path.join(javaHomeEnv, 'bin', 'java');
    }

    // MacOS specific logic to avoid popping up a dialog window.
    // See: http://stackoverflow.com/questions/14292698/how-do-i-check-if-the-java-jdk-is-installed-on-mac.
    if (platform.isMacOS) {
      try {
        var javaHomeOutput = runCheckedSync(
            <String>['/usr/libexec/java_home'],
            hideStdout: true);
        if (javaHomeOutput != null) {
          final List<String> javaHomeOutputSplit = javaHomeOutput.split('\n');
          if ((javaHomeOutputSplit != null) &&
              (javaHomeOutputSplit.isNotEmpty)) {
            final String javaHome = javaHomeOutputSplit[0].trim();
            return fs.path.join(javaHome, 'bin', 'java');
          }
        }
      } catch (_) {/* ignore */}
    }

    // Fallback to PATH based lookup.
    return os.which(_javaExecutable)?.path;
  }

  Map<String, String>? _sdkManagerEnv;

  /// Returns an environment with the Java folder added to PATH for use in calling
  /// Java-based Android SDK commands such as sdkmanager and avdmanager.
  Map<String, String> get sdkManagerEnv {
    var env = _sdkManagerEnv;
    if (env == null) {
      // If we can locate Java, then add it to the path used to run the Android SDK manager.
      env = <String, String>{};
      final javaBinary = findJavaBinary();
      if (javaBinary != null) {
        final path = platform.environment['PATH'];
        if (path != null) {
          env['PATH'] = fs.path.dirname(javaBinary) +
              os.pathVarSeparator +
              path;
        }
      }
      _sdkManagerEnv = env;
    }

    return env;
  }

  /// Returns the version of the Android SDK manager tool or null if not found.
  String? get sdkManagerVersion {
    if (!processManager.canRun(sdkManagerPath))
      throw ToolExit(
          'Android sdkmanager not found. Update to the latest Android SDK to resolve this.');
    final ProcessResult result = processManager.runSync(
        <String>[sdkManagerPath, '--version'],
        environment: sdkManagerEnv);
    if (result.exitCode != 0) {
      printTrace(
          'sdkmanager --version failed: exitCode: ${result.exitCode} stdout: ${result.stdout} stderr: ${result.stderr}');
      return null;
    }
    return result.stdout.trim();
  }

  @override
  String toString() => 'AndroidSdk: $directory';
}

class AndroidSdkVersion implements Comparable<AndroidSdkVersion> {
  AndroidSdkVersion._(
    this.sdk, {
    required this.sdkLevel,
    required this.platformName,
    required this.buildToolsVersion,
  })  : assert(sdkLevel != null),
        assert(platformName != null),
        assert(buildToolsVersion != null);

  final AndroidSdk sdk;
  final int sdkLevel;
  final String platformName;
  final Version buildToolsVersion;

  String get buildToolsVersionName => buildToolsVersion.toString();

  String get androidJarPath => getPlatformsPath('android.jar');

  String get aaptPath => getBuildToolsPath('aapt');

  List<String> validateSdkWellFormed() {
    var path = _exists(androidJarPath);
    if (path != null)
      return <String>[path];

    path = _canRun(aaptPath);
    if (path != null) return <String>[path];

    return <String>[];
  }

  String getPlatformsPath(String itemName) {
    return fs.path.join(sdk.directory, 'platforms', platformName, itemName);
  }

  String getBuildToolsPath(String binaryName) {
    return fs.path
        .join(sdk.directory, 'build-tools', buildToolsVersionName, binaryName);
  }

  @override
  int compareTo(AndroidSdkVersion other) => sdkLevel - other.sdkLevel;

  @override
  String toString() =>
      '[${sdk.directory}, SDK version $sdkLevel, build-tools $buildToolsVersionName]';

  String? _exists(String path) {
    if (!fs.isFileSync(path)) return 'Android SDK file not found: $path.';
    return null;
  }

  String? _canRun(String path) {
    if (!processManager.canRun(path))
      return 'Android SDK file not found: $path.';
    return null;
  }
}
