import 'dart:convert' as convert;
import 'dart:io';

final Future<bool> isRunningInDockerContainer = _isRunningInDockerContainer();

Future<bool> _isRunningInDockerContainer() async {
  final cgroup = File('/proc/1/cgroup');

  if (!cgroup.existsSync()) {
    return false;
  }

  return '' != await cgroup
    .openRead()
    .transform(convert.utf8.decoder)
    .transform(const convert.LineSplitter())
    .firstWhere((l) => l.contains('/docker'), orElse: () => '');
}