import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate' as isolates;

import 'package:lightning_runner/lightning/contexts/after_reload_context.dart';
import 'package:lightning_runner/lightning/contexts/before_reload_context.dart';
import 'package:collection/collection.dart';
import 'package:lightning_runner/lightning/lightning_result.dart';
import 'package:lightning_runner/lightning/utils/docker.dart';
import 'package:lightning_runner/lightning/extensions/files.dart';
import 'package:lightning_runner/lightning/utils/pub.dart';
import 'package:lightning_runner/lightning/utils/strings.dart';
import 'package:lightning_runner/lightning/utils/vm.dart';

import 'package:path/path.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:vm_service/vm_service.dart';
import 'package:watcher/watcher.dart';

class LightningRunner {
  final bool Function(BeforeReloadContext ctx)? onBeforeReload;
  final void Function(AfterReloadContext ctx)? onAfterReload;
  final void Function(Directory directory)? onDirectoryWatching;
  final void Function(File file)? onFileChange;
  final void Function(File file)? onFileCreate;
  final void Function(File file)? onFileDelete;

  final Duration debounceInterval;
  final _watchedStreams = <StreamSubscription<List<WatchEvent>>>{};
  final bool watchDependencies;
  late VmService _vmService;


  LightningRunner({
    this.watchDependencies = true,
    this.debounceInterval = const Duration(seconds: 1),
    this.onBeforeReload,
    this.onAfterReload,
    this.onDirectoryWatching,
    this.onFileChange,
    this.onFileCreate,
    this.onFileDelete,
  }) {
    if (!File('pubspec.yaml').existsSync()) {
      throw StateError('''
        Error: [pubspec.yaml] file not found in current directory.
        For hot code reloading to function properly, Dart needs to be run from the root of your project.''');
    }
  }

  Future<void> _registerWatchers() async {
    if (_watchedStreams.isNotEmpty) {
      await stop();
    }

    List<String> watchList = ['bin', 'lib', 'test'];

    if (watchDependencies) {
      final pkgConfigURL = await isolates.Isolate.packageConfig;

      watchList.add((await packagesFile).path);

      if (pkgConfigURL != null) {
        if (pkgConfigURL.path.endsWith('.json')) {
          json
            .decode(await File(pkgConfigURL.toFilePath()).readAsString())['packages']
            .map((dynamic v) => v['rootUri'].toString())
            .map((dynamic rootUri) => rootUri.toString().startsWith('../') ? rootUri.substring(1) : rootUri)
            .map((dynamic rootUri) => Uri.parse(rootUri.toString()).toFilePath())
            .forEach(watchList.add);
        } else {
          await pkgConfigURL
            .readLineByLine()
            .where((l) => !l.startsWith('#') && l.contains(':'))
            .map((l) => Uri.parse(substringAfter(l, ':')).toFilePath())
            .forEach(watchList.add);
        }
      }
    }

    watchList = watchList.map(absolute).map(normalize).toSet().toList();
    watchList.sort();

    final isDockerized = await isRunningInDockerContainer;

    final watchers = <Watcher>[];
    for (final path in watchList) {
      if (path == pubCacheDir.path || isWithin(pubCacheDir.path, path)) {
        continue;
      }

      if (watchers.where((w) => path == w.path || isWithin(w.path, path)).isNotEmpty) {
        continue;
      }

      final fileType = FileSystemEntity.typeSync(path);
      if (fileType == FileSystemEntityType.file) {
        watchers.add(isDockerized //
          ? PollingFileWatcher(path, pollingDelay: debounceInterval) //
          : FileWatcher(path) //
        );
      } else if (fileType == FileSystemEntityType.notFound) {
        watchers.add(PollingDirectoryWatcher(path, pollingDelay: debounceInterval));
      } else {
        watchers.add(isDockerized
            ? PollingDirectoryWatcher(path, pollingDelay: debounceInterval)
            : DirectoryWatcher(path));
      }
    }

    for (final watcher in watchers) {
      if (onDirectoryWatching != null) {
        onDirectoryWatching!(Directory(watcher.path));
      }

      final watchedStream = watcher.events
        .debounceBuffer(debounceInterval)
        .listen(_onFilesModified);

      await watcher.ready;
      _watchedStreams.add(watchedStream);
    }
  }

  Future<LightningResult> _reloadCode(final List<WatchEvent>? changes, final bool force) async {
    final packages = await packagesFile;
    final isPackagesFileChanged = null != changes?.firstWhereOrNull((c) => c.path.endsWith('.packages') &&
      File(c.path).absolute.path == packages.path
    );

    final reloadReports = <IsolateRef, ReloadReport>{};
    final failedReloadReports = <IsolateRef, ReloadReport>{};

    for (final isolateRef in (await _vmService.getVM()).isolates ?? <IsolateRef>[]) {
      if (isolateRef.id == null) {
        continue;
      }

      var noVeto = true;
      if (onBeforeReload != null) {
        if (changes?.isEmpty ?? true) {
          noVeto = onBeforeReload?.call(BeforeReloadContext(null, isolateRef)) ?? true;
        } else {
          for (final change in changes ?? <WatchEvent>[]) {
            if (!(onBeforeReload?.call(BeforeReloadContext(change, isolateRef)) ?? true)) {
              noVeto = false;
            }
          }
        }
      }

      if (noVeto) {
        try {
          final reloadReport = await _vmService.reloadSources(isolateRef.id!,
            force: force,
            packagesUri: isPackagesFileChanged ? packages.uri.toString() : null
          );

          if (!(reloadReport.success ?? false)) {
            failedReloadReports[isolateRef] = reloadReport;
          }

          reloadReports[isolateRef] = reloadReport;
        } on SentinelException catch (ex) {
          // happens when the isolate has been garbage collected in the meantime
        }
      } else {
      }
    }

    if (isPackagesFileChanged) {
      await _registerWatchers();
    }

    if (reloadReports.isEmpty) {
      return LightningResult.skipped;
    }

    if (failedReloadReports.isEmpty) {
      onAfterReload?.call(AfterReloadContext(changes, reloadReports, LightningResult.succeeded));
      return LightningResult.succeeded;
    }

    if (failedReloadReports.length == reloadReports.length) {
      onAfterReload?.call(AfterReloadContext(changes, reloadReports, LightningResult.failed));
      return LightningResult.failed;
    }

    onAfterReload?.call(AfterReloadContext(changes, reloadReports, LightningResult.partiallySucceeded));
    return LightningResult.partiallySucceeded;
  }

  Future<void> _onFilesModified(final List<WatchEvent> changes) async {
    final packages = await packagesFile;
    changes.retainWhere((ev) => ev.path.endsWith('.dart') || ev.path == packages.path);

    if (changes.isEmpty) {
      return;
    }

    if (onFileChange != null) {
      for (final event in changes) {
        if (event.type == ChangeType.REMOVE && onFileDelete != null) {
          onFileDelete!(File(event.path));
        }

        if (event.type == ChangeType.ADD && onFileCreate != null) {
          onFileCreate!(File(event.path));
        }

        if (event.type == ChangeType.MODIFY && onFileDelete != null) {
          onFileChange!(File(event.path));
        }
      }
    }

    await _reloadCode(changes, false);
  }

  bool get isWatching => _watchedStreams.isNotEmpty;

  Future<LightningResult> reloadCode({final bool force = false}) async {
    return _reloadCode(null, force);
  }

  Future<void> watch () async {
    _vmService = await createVmService();
    await _registerWatchers();
  }

  Future<void> stop() async {
    if (_watchedStreams.isNotEmpty) {
      print('Stopping to watch paths...');
      await Future.wait<dynamic>(_watchedStreams.map((s) => s.cancel()));
      _watchedStreams.clear();
    } else {
      print('Was not watching any paths.');
    }

    // to prevent "Unhandled exception: reloadSources: (-32000) Service connection disposed"
    await Future<void>.delayed(const Duration(seconds: 2));

    await _vmService.dispose();
  }
}