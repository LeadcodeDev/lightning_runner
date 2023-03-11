import 'package:lightning_runner/lightning/lightning_result.dart';
import 'package:vm_service/vm_service.dart';
import 'package:watcher/watcher.dart';

class AfterReloadContext {
  final Iterable<WatchEvent>? events;
  final Map<IsolateRef, ReloadReport> reloadReports;
  final LightningResult result;

  AfterReloadContext(this.events, this.reloadReports, this.result);
}