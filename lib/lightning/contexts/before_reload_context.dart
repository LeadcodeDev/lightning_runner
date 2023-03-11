import 'package:vm_service/vm_service.dart';
import 'package:watcher/watcher.dart';

class BeforeReloadContext {
  final WatchEvent? event;
  final IsolateRef isolate;

  BeforeReloadContext(this.event, this.isolate);
}