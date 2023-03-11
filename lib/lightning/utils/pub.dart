import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;

Future<File> _getPackagesFile() async {
  final path = (await Isolate.packageConfig)?.toFilePath() ?? '.packages';
  return File(path).absolute;
}

final Future<File> packagesFile = _getPackagesFile();

Directory _getPubCacheDir() {
  final env = Platform.environment;
  final path = env['PUB_CACHE'] ?? (Platform.isWindows
    ? '${env['APPDATA']}\\Pub\\Cache'
    : '${env['HOME']}/.pub-cache');

  return Directory(p.normalize(path)).absolute;
}

final Directory pubCacheDir = _getPubCacheDir();